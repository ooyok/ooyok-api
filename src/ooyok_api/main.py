from fastapi import FastAPI

# From python packages which are designated by empty __init__.py file
# Anything defined at the module’s top level—classes, functions, constants, and variables can normally be imported by another module
from ooyok_api.api import health
from ooyok_api.core.config import Settings


def create_app(settings: Settings | None = None) -> FastAPI:
    # App factory: build a new app on each call instead of one global at import time.
    # Tests pass their own Settings; production reads the environment.
    # Run locally with: uv run uvicorn ooyok_api.main:create_app --factory --reload
    settings = settings or Settings()

    app = FastAPI(title="ooyok API", version=settings.app_version)
    app.state.settings = settings
    app.include_router(health.router)
    return app
