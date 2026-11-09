#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): fix and format each Python file Claude edits, like "format on save".
# The edit has already happened, so exit 2 can't undo it; it sends leftover lint errors
# (ones Ruff can't auto-fix) back to Claude so it fixes them right away.

# set: a configuration command for current shell script
# -e: exit immediately, if any command returns a non-zero exit code
# -u: Treat references to unset variables as errors not empty string
# -o pipefail: if any single part of the pipeline fails (returns a non-zero exit code), the overall exit status of the entire pipeline will be an error.
set -euo pipefail

# jq: a json processor
# claude will pass a json to indicate what it has done on what file
file_path=$(jq -r '.tool_input.file_path // empty')
# ignore non-python files
[[ "$file_path" == *.py ]] || exit 0
cd "$CLAUDE_PROJECT_DIR"

# script status indicator
status=0
# Fix before formatting: removing an unused import can leave blank lines for the formatter to tidy.
# standard streams: {-: stdin, 1: stdout, 2: stderr}
# 2>&1: direct stderr to stdout. By default, $(...) captures stdout only.
# - stdout (file descriptor 1) → captured into lint variable
# - stderr (file descriptor 2) → goes to the terminal
lint=$(uv run ruff check --fix --quiet "$file_path" 2>&1) || status=2
fmt=$(uv run ruff format --quiet "$file_path" 2>&1) || status=2

# if status is non zero (has error), then direct the original lint and fmt output to stderr
if (( status )); then
  printf '%s\n%s\n' "$lint" "$fmt" >&2
fi
exit "$status"
