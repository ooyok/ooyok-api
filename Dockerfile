# API image for Cloud Run. Two stages: the builder installs everything into /app/.venv with uv,
# and the runtime stage copies only that folder, so build tools and dev dependencies never ship.
# Both stages must use the same base image: the venv links to that image's Python.

FROM python:3.14-slim-trixie AS builder
# uv is copied from its official image; match the version in the uv_build range in pyproject.toml.
# ghcr.io/astral-sh is official github container registry path for uv
COPY --from=ghcr.io/astral-sh/uv:0.13.6 /uv /bin/uv

# UV_COMPILE_BYTECODE: compile .pyc files now so each cold start doesn't.
# https://docs.astral.sh/uv/guides/integration/docker/#compiling-bytecode

# UV_PYTHON_DOWNLOADS: use the image's Python, never download another one.
# The setting works as safe guard if there is a python version mismatch between py_version in image and requires-python = ">=3.14" spec in pyproject.toml
# Mismatch: log the error
ENV UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# Dependencies first, without the app. Docker reuses this layer until pyproject.toml or uv.lock
# changes, so editing code doesn't reinstall dependencies.
# Install the locked production dependencies into the virtual environment, but do not install development tools or the application package yet.
# This is for better layer cache
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

# Then the app itself. --no-editable installs it into .venv as a normal package,
# so the runtime stage needs no source folder. README.md is the package readme in pyproject.toml.
COPY README.md ./
COPY src ./src
# --no-editable breaks the link between the environment and your source code directory -> disable hot-reload
RUN uv sync --locked --no-dev --no-editable


FROM python:3.14-slim-trixie AS runtime

# Run as an unprivileged user. The venv stays owned by root, so the app can't modify its own code.
# --system: the group and user are intended for system service not normal human user
# --gid: existing group `app`
# --no-create-home: don't cerate home directory
RUN groupadd --system app && useradd --system --gid app --no-create-home app
COPY --from=builder /app/.venv /app/.venv

# $PATH: list of directories that terminal will search for executable programs
# PATH: `uvicorn` and `python` resolve to the venv.
# add the /app/.venv/bin to existing $PATH
# PYTHONUNBUFFERED: write logs immediately so Cloud Logging gets them even if the process dies.
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

# Switch to non-root user in case that the container be compromised
USER app
EXPOSE 8080

# Cloud Run sets PORT; 8080 is the fallback for local runs. One worker per container (ADR 0007).
# sh expands ${PORT}; `exec` then replaces sh with uvicorn, so uvicorn is PID 1 and receives
# SIGTERM directly when Cloud Run stops the instance.
CMD ["sh", "-c", "exec uvicorn ooyok_api.main:create_app --factory --host 0.0.0.0 --port ${PORT:-8080}"]
