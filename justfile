# Task runner: short names for common commands (the equivalent of npm scripts).
# just is a dev dependency, so call it as `uv run just <recipe>`. `uv run just` lists recipes.
# Each recipe also uses `uv run`, so it works whether or not .venv is activated.

# List recipes
# This is the default recipe. `uv run just` dose not specify any recipe, so default will run
# @ suppresses printing command itself but not output
default:
    @just --list

# Install dependencies and git hooks (run once after cloning repository)
setup:
    uv sync
    uv run pre-commit install

# Run the API with auto-reload on http://localhost:8000
# uvicorn: webserver
# --factory: treat create_app as an application factory and call it to create the FastAPI app
# --reload: watch the source files and automatically restart
dev:
    uv run uvicorn ooyok_api.main:create_app --factory --reload

# Run all tests
test *args:
    uv run pytest {{args}}

# Run only fast unit tests (used by the pre-push hook)
test-unit:
    uv run pytest tests/unit -q

# Run all tests with a coverage report; fails under the threshold in pyproject.toml
test-cov:
    uv run pytest --cov --cov-report=term-missing

# Check lint, formatting, and types without changing files (what CI runs)
lint:
    uv run ruff check .
    uv run ruff format --check .
    uv run mypy

# Auto-fix lint issues and format code
fix:
    uv run ruff check --fix .
    uv run ruff format .

# Run every pre-commit hook against all files
hooks:
    uv run pre-commit run --all-files

# Build the API image and run it in the background on http://localhost:8080
# --wait: return only after the healthcheck in docker-compose.yml passes
up:
    docker compose up --build --detach --wait

# Stop and remove the containers
down:
    docker compose down

# Build and start the container, check that /health returns the injected version `smoke`, then stop it
smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    # Always stop the container, even when a check fails.
    trap 'docker compose down' EXIT
    APP_VERSION=smoke docker compose up --build --detach --wait
    response=$(curl --fail --silent --show-error http://localhost:8080/health)
    if ! jq -e '.status == "ok" and .version == "smoke"' <<<"$response" >/dev/null; then
        echo "Unexpected /health response: $response" >&2
        exit 1
    fi
    echo "Smoke test passed: $response"
