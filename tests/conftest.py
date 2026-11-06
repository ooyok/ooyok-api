# Shared pytest fixtures. pytest loads this file automatically; tests request a fixture by naming it as a parameter.
# By default, pytest fixtures run before each test function that requests them
from collections.abc import AsyncIterator

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from ooyok_api.core.config import Settings
from ooyok_api.main import create_app


@pytest.fixture
def settings() -> Settings:
    # Explicit values instead of reading the real environment, so tests behave the same everywhere.
    # A test module can override this fixture to try other settings.
    return Settings(app_version="test-sha")


@pytest.fixture
def app(settings: Settings) -> FastAPI:
    # A fresh app per test: overrides made in one test can't leak into another.
    return create_app(settings)


@pytest.fixture
async def client(app: FastAPI) -> AsyncIterator[AsyncClient]:
    # ASGITransport calls the app in-process: no server, no network, fast.
    # Follow the doc: https://fastapi.tiangolo.com/advanced/async-tests/#in-detail
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
