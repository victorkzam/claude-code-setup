#!/bin/bash
# PreToolUse(Write|Edit) — block edits to secret / credential / key material.
# Patterns broadened from gitleaks/trufflehog default rule families. Path is
# lowercased first so .PEM / Config.SWIFT / .Env are caught too.

# Fail closed: this hook parses tool input with jq. Without jq we cannot safely
# decide, so block rather than silently letting an unchecked edit through.
command -v jq >/dev/null 2>&1 || { echo "jq required for this hook — install jq or remove it from settings.json" >&2; exit 2; }

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
[ -z "$FILE" ] && exit 0
LC=$(echo "$FILE" | tr '[:upper:]' '[:lower:]')

case "$LC" in
  *.env|*.env.*|*.envrc|*credentials*|*secret*|*config.swift| \
  *.pem|*.key|*.p8|*.pfx|*.jks|*.keystore| \
  *id_rsa*|*id_ed25519*| \
  */.aws/credentials|*/.aws/config|*aws_secret*| \
  */secrets/*|*/.ssh/*|*/.gnupg/*| \
  *service-account*.json|*gcp*key*.json)
    echo "Blocked: cannot edit sensitive file: $FILE" >&2
    exit 2
    ;;
esac
exit 0
