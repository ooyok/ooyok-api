from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from ooyok_api.core.config import Settings

# No /v1 prefix: /health is operational, not part of the versioned product API.
# Not /healthz: Cloud Run reserves some paths ending in "z".
router = APIRouter(tags=["ops"])


# Declare return Type
class HealthResponse(BaseModel):
    status: Literal["ok"]
    version: str


# The dependable/dependency for the dependency injection
def get_settings(request: Request) -> Settings:
    # Read the settings the app was built with, so tests can inject their own via create_app().
    settings: Settings = request.app.state.settings
    return settings


@router.get("/health")
async def health(settings: Annotated[Settings, Depends(get_settings)]) -> HealthResponse:
    # Liveness only: answers "is the process up?" and touches no DB or Redis,
    # so a dependency outage doesn't get healthy instances restarted.
    return HealthResponse(status="ok", version=settings.app_version)
