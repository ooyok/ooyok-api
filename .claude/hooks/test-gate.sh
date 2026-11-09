#!/usr/bin/env bash
# Stop hook: Claude can't end its turn while unit tests or type checks fail.
# Exit 2 cancels the stop and sends stderr back to Claude, so it keeps working on the failure.
set -euo pipefail

input=$(cat)

# stop_hook_active is true when Claude is already continuing because this hook blocked it once.
# Let it stop the second time instead of looping forever on a failure it can't fix.
[[ $(jq -r '.stop_hook_active // false' <<<"$input") == "true" ]] && exit 0

cd "$CLAUDE_PROJECT_DIR"

# Nothing to verify if no Python or dependency files have uncommitted changes (Q&A or docs-only turns).
# This looks at the whole working tree, not just this turn, so it also runs while earlier edits are uncommitted.
[[ -z $(git status --porcelain -- '*.py' pyproject.toml uv.lock) ]] && exit 0

# Fast checks only; API and integration tests run with `just test` and in CI.
if ! output=$(uv run just test-unit 2>&1 && uv run mypy 2>&1); then
  echo "Unit tests or mypy failed. Fix them before finishing:" >&2
  tail -n 60 <<<"$output" >&2
  exit 2
fi
