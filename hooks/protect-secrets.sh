#!/bin/bash
# PreToolUse(Write|Edit|MultiEdit|NotebookEdit) — block edits to secret /
# credential / key material. Patterns broadened from gitleaks/trufflehog
# default rule families. Path is lowercased first so .PEM / Config.SWIFT /
# .Env are caught too. Directory checks run before the template allowlist so
# a template-named file inside a secrets/.ssh/.aws directory still blocks.

if ! command -v jq >/dev/null 2>&1; then
  echo "cw: jq not found, hook skipped" >&2
  exit 0
fi

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // .tool_input.notebook_path // empty')
[ -z "$FILE" ] && exit 0
LC=$(echo "$FILE" | tr '[:upper:]' '[:lower:]')

# Directory checks first: anything under secrets/, .ssh/, or .aws/ is blocked
# regardless of filename, even a template-allowlisted name.
case "$LC" in
  */secrets/*|*/.ssh/*|*/.aws/*|secrets/*|.ssh/*|.aws/*|*/.gnupg/*|.gnupg/*)
    echo "Blocked: cannot edit sensitive file: $FILE" >&2
    exit 2
    ;;
esac

# Allowlist: secret-file TEMPLATES that carry key NAMES only, never values.
case "$(basename "$LC")" in
  .env.example|.env.sample|.env.template|env.example)
    exit 0
    ;;
esac

case "$LC" in
  *.env|*.env.*|*.envrc|*credentials*|*secret*|*config.swift| \
  *.pem|*.key|*.p8|*.pfx|*.jks|*.keystore| \
  *id_rsa*|*id_ed25519*| \
  *.gnupg/*| \
  *service-account*.json|*gcp*key*.json| \
  *.p12|*.netrc|*id_dsa*|*id_ecdsa*| \
  *.tfstate|*.tfstate.backup)
    echo "Blocked: cannot edit sensitive file: $FILE" >&2
    exit 2
    ;;
esac
exit 0
