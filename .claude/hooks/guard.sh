#!/usr/bin/env bash
# PreToolUse hook (Edit|Write): block edits to Alembic migrations that are already on origin/main.
# A merged migration may have run on staging or prod; editing it makes those databases disagree
# with the code. Add a new migration instead.
# Dormant until Alembic is added (M1): no path matches until src/ooyok_api/migrations/versions/ exists.
# Fixed path rules (.env*, *.tfstate*) are deny rules in settings.json; this hook is for checks that need git.
# Claude Code sends the pending tool call as JSON on stdin. Exit 2 blocks the call and shows
# stderr to Claude; exit 0 lets it through.

# set the shell script configuration
set -euo pipefail

# capture the file that claude has worked on
file_path=$(jq -r '.tool_input.file_path // empty')
[[ "$file_path" == */migrations/versions/*.py ]] || exit 0

# go to claude working directory
cd "$CLAUDE_PROJECT_DIR"
rel_path=${file_path#"$CLAUDE_PROJECT_DIR"/}

# origin/main is as of the last `git fetch`. A new migration isn't there yet, so it's allowed.
if git cat-file -e "origin/main:$rel_path" 2>/dev/null; then
  echo "Blocked by .claude/hooks/guard.sh: $rel_path is already on origin/main and may have run on staging or prod. Create a new migration instead." >&2
  exit 2
fi
