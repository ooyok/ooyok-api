# Task runner: short names for common commands (the equivalent of npm scripts).
# just is a dev dependency, so call it as `uv run just <recipe>`. `uv run just` lists recipes.
# Each recipe also uses `uv run`, so it works whether or not .venv is activated.

# List recipes
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
