#!/bin/bash
# scripts/merge-settings.sh — the SOLE writer of $CLAUDE_DIR/settings.json.
#
# Missing target        -> write the repo template VERBATIM (design M3: the
#                          example IS the intended fresh-adopter config; the
#                          _comment_* keys are instructional and ship as-is).
# Existing target       -> deterministic jq merge LIMITED to exactly two areas:
#                          `.hooks` and `.permissions.allow`. Every other key the
#                          adopter has (model, statusLine, defaultMode, env, any
#                          personal key) is UNTOUCHED and is never added from the
#                          template either (deliberately narrow).
#
# Hook reconciliation is BASENAME-KEYED. An existing hook command is classified by
# TOKEN-ANCHORED matching: the command string is split on whitespace, each token is
# stripped of surrounding quotes, and the entry is MANAGED only if some token's
# basename is EXACTLY a manifest-listed hook FILENAME (protect-branches.sh,
# protect-secrets.sh, orchestrator-delegate-guard.sh, design-scope-guard.sh,
# syntax-check.sh — derived from manifest.txt). This matches both the
# config-dir-aware and old `~/.claude` invocation forms while never misreading
# a filename mentioned only in echo/log text. Managed entries are REPLACED by
# the template's current entry for that filename (landing command-string
# upgrades WITHOUT duplication). Hook entries
# referencing NO manifest filename are FOREIGN and preserved verbatim. Template
# hook entries not already present are added. `.permissions.allow` is a concat +
# ORDER-PRESERVING dedup (first occurrence wins; adopter entries are never dropped
# and the array is never reordered, which keeps the fresh-verbatim write a fixed
# point across repeat runs).
#
# Semantics notes:
#   * Scalar-wins / null-safe: this script never uses recursive object merge, so a
#     null template value can never delete an adopter key.
#   * Malformed nested shapes — a non-object `.hooks` / `.permissions`, a
#     non-array `.permissions.allow`, a non-array `.hooks.<event>` value, a
#     non-object element of one, a non-array inner `.hooks` list, a non-object
#     inner hook entry, or a non-string `.command` on one — are REJECTED up front
#     with an explicit exit-1 refusal on stderr in BOTH modes, so a bad shape
#     never reaches jq as a raw exit-5 crash.
#   * The unchanged/write-skip decision is SEMANTIC (sorted-compact canonical
#     compare of target vs merged), not raw-byte: formatting-only differences (e.g.
#     the template's hand-authored blank lines) never trigger a phantom rewrite.
#
# Global contract (design v4): Bash 3.2; set -euo pipefail; never reads stdin /
# never prompts; CCS-STATUS:<action>:<path> + diffs (dry-run only) on stdout;
# refusals on stderr; atomic writes; jq fail-closed. Exit 0 success (incl. the
# CCS-STATUS:unchanged no-op) / 1 refusal-partial / 2 usage-internal.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P )"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

SOURCE="$REPO_ROOT/settings.example.json"
MANIFEST="$SCRIPT_DIR/manifest.txt"
TARGET="$CLAUDE_DIR/settings.json"
MERGED_TMP=""
trap 'rm -f "$MERGED_TMP"' EXIT

usage() { printf 'usage: merge-settings.sh (--dry-run | --apply) [--backup-dir <path>]\n'; }
usage_err() { usage >&2; exit 2; }

# ccs_hook_names_json — JSON array of the managed hook basenames from the manifest
# (hooks/*.sh lines). Basenames are plain .sh filenames, so raw quoting is safe.
ccs_hook_names_json() {
  local rel base out=""
  while IFS= read -r rel || [ -n "$rel" ]; do
    case "$rel" in
      hooks/*.sh)
        base="${rel#hooks/}"
        if [ -z "$out" ]; then out="\"$base\""; else out="$out,\"$base\""; fi
        ;;
    esac
  done < "$MANIFEST"
  printf '[%s]' "$out"
}

# The merge program. Reconciliation is basename-keyed; see the file header. The
# $-prefixed tokens below are jq variables, not shell expansions (SC2016).
# shellcheck disable=SC2016
JQ_MERGE='
def basename_of: sub(".*/"; "");
def strip_surround_quotes:
  ([34,39] | implode) as $q
  | sub("^[" + $q + "]+"; "") | sub("[" + $q + "]+$"; "");
def is_managed($c):
  any($c | splits("[[:space:]]+");
      (strip_surround_quotes | basename_of) as $b
      | ($names | index($b)) != null);
def dedup: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
def strip_managed:
  if . == null then {}
  else with_entries(
         .value = ((.value // [])
           | map(.hooks = ((.hooks // []) | map(select(is_managed(.command // "") | not))))
           | map(select((.hooks | length) > 0)))
       )
       | with_entries(select((.value | length) > 0))
  end;
def add_group($g):
  (map(.matcher) | index($g.matcher)) as $i
  | if $i == null then . + [$g]
    else (.[$i]) as $ex
      | ($g.hooks | map(select(. as $e | ($ex.hooks | any(. == $e)) | not))) as $new
      | .[$i].hooks = ($ex.hooks + $new)
    end;
def merge_hooks($tpl):
  ((. // {}) | strip_managed) as $base
  | (reduce ($tpl | to_entries[]) as $te ({};
       .[$te.key] = (($base[$te.key] // []) | reduce ($te.value[]) as $g (.; add_group($g)))
     )) as $withtpl
  | reduce ($base | keys_unsorted[]) as $k ($withtpl;
      if ($tpl | has($k)) then . else .[$k] = $base[$k] end);
($template[0]) as $t
| .hooks = ((.hooks // {}) | merge_hooks($t.hooks // {}))
| .permissions = (.permissions // {})
| .permissions.allow = (((.permissions.allow // []) + ($t.permissions.allow // [])) | dedup)
'

# ccs_build_merged <target> — emit the merged JSON for an existing object target.
ccs_build_merged() {
  jq --indent 2 --slurpfile template "$SOURCE" --argjson names "$( ccs_hook_names_json )" \
     "$JQ_MERGE" "$1"
}

# ccs_validate_object <target> — refuse (exit 1) unparseable / non-object targets
# and malformed nested shapes. A syntactically-valid object whose `.hooks` /
# `.permissions` is not an object, whose `.permissions.allow` is not an array, OR
# any NESTED shape the merge jq actually walks (every `.hooks.<event>` value; each
# element of it; that element's own `.hooks` inner list, if present; and each
# inner entry's `.command`, where the merge does a string split/match on it) is
# rejected here (both modes) so a bad shape never reaches jq as a raw exit-5
# crash — only the documented 0/1/2 exit contract (see header) is ever observed.
ccs_validate_object() {
  local kind msg
  if ! jq empty "$1" >/dev/null 2>&1; then
    ccs_die 1 "target exists but is not valid JSON: $1"
  fi
  kind="$( jq -r 'type' "$1" )"
  if [ "$kind" != "object" ]; then
    ccs_die 1 "target is a JSON $kind, not an object: $1"
  fi
  msg="$( jq -r '
    (.hooks // null) as $h
    | (.permissions // null) as $p
    | def hookmsg:
        ($h // {}) | to_entries[]
        | .key as $ename
        | if (.value | type) != "array" then
            "field .hooks." + $ename + " must be a JSON array, not a " + (.value | type)
          else
            (.value[] |
              if type != "object" then
                "field .hooks." + $ename + "[] entry must be a JSON object, not a " + type
              elif has("hooks") and ((.hooks | type) != "array") then
                "field .hooks." + $ename + "[].hooks must be a JSON array, not a " + (.hooks | type)
              else
                (.hooks // [])[] |
                  if type != "object" then
                    "field .hooks." + $ename + "[].hooks[] entry must be a JSON object, not a " + type
                  elif has("command") and ((.command | type) != "string") then
                    "field .hooks." + $ename + "[].hooks[].command must be a JSON string, not a " + (.command | type)
                  else empty
                  end
              end
            )
          end;
    if ($h != null and ($h | type) != "object")
      then "field .hooks must be a JSON object, not a " + ($h | type)
    elif ($p != null and ($p | type) != "object")
      then "field .permissions must be a JSON object, not a " + ($p | type)
    elif ($p != null and ($p.allow != null) and ($p.allow | type) != "array")
      then "field .permissions.allow must be a JSON array, not a " + ($p.allow | type)
    elif ($h != null)
      then ([hookmsg] | first) // ""
    else "" end' "$1" )"
  if [ -n "$msg" ]; then
    ccs_die 1 "$msg: $1"
  fi
}

# ccs_same_content <a> <b> — true when two JSON files are SEMANTICALLY identical
# (sorted-compact canonical form), so formatting-only differences never count as a
# change. Fails closed (non-equal) if either file will not canonicalize.
ccs_same_content() {
  local ca cb
  ca="$( jq -S -c . "$1" )" || return 1
  cb="$( jq -S -c . "$2" )" || return 1
  [ "$ca" = "$cb" ]
}

# ccs_do_dry_run — preview only; unified diff of current -> merged, never mutates.
ccs_do_dry_run() {
  if [ ! -e "$TARGET" ]; then
    diff -u /dev/null "$SOURCE" || true
    return 0
  fi
  ccs_validate_object "$TARGET"
  MERGED_TMP="$( mktemp "${TMPDIR:-/tmp}/ccs-settings.XXXXXX" )"
  ccs_build_merged "$TARGET" > "$MERGED_TMP"
  if ccs_same_content "$TARGET" "$MERGED_TMP"; then
    ccs_status unchanged "$TARGET"
  else
    diff -u "$TARGET" "$MERGED_TMP" || true
  fi
}

# ccs_backup_dir_for — resolve the (optionally threaded) backup run dir.
ccs_backup_dir_for() {
  if [ -n "$BACKUP_DIR" ]; then
    ccs_backup_run_dir --backup-dir "$BACKUP_DIR"
  else
    ccs_backup_run_dir
  fi
}

# ccs_apply_fresh — no existing target: install the template verbatim (M3).
ccs_apply_fresh() {
  local run_dir
  run_dir="$( ccs_backup_dir_for )"
  ccs_atomic_install "$SOURCE" "$TARGET"
  ccs_receipt_append "$run_dir" merged "$TARGET" ""
  ccs_status merged "$TARGET"
}

# ccs_apply_existing — merge into an existing object target; no-op when unchanged.
ccs_apply_existing() {
  local run_dir
  ccs_validate_object "$TARGET"
  MERGED_TMP="$( mktemp "${TMPDIR:-/tmp}/ccs-settings.XXXXXX" )"
  ccs_build_merged "$TARGET" > "$MERGED_TMP"
  if ccs_same_content "$TARGET" "$MERGED_TMP"; then
    ccs_status unchanged "$TARGET"
    return 0
  fi
  run_dir="$( ccs_backup_dir_for )"
  cp "$TARGET" "$run_dir/settings.json"
  ccs_atomic_install "$MERGED_TMP" "$TARGET"
  ccs_receipt_append "$run_dir" merged "$TARGET" "$run_dir/settings.json"
  ccs_status merged "$TARGET"
}

main() {
  local mode=""
  BACKUP_DIR=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) if [ -n "$mode" ]; then usage_err; fi; mode="dry" ;;
      --apply)   if [ -n "$mode" ]; then usage_err; fi; mode="apply" ;;
      --backup-dir) shift; if [ $# -eq 0 ]; then usage_err; fi; BACKUP_DIR="$1" ;;
      -h|--help) usage; exit 0 ;;
      *) usage_err ;;
    esac
    shift
  done
  if [ -z "$mode" ]; then usage_err; fi

  command -v jq >/dev/null 2>&1 || ccs_die 1 "jq is required but was not found on PATH"
  refuse_symlink "$TARGET"

  if [ "$mode" = "dry" ]; then
    ccs_do_dry_run
  elif [ ! -e "$TARGET" ]; then
    ccs_apply_fresh
  else
    ccs_apply_existing
  fi
}

main "$@"
