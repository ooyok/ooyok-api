import pytest

from ooyok_api.core.config import Settings


def test_app_version_defaults_to_dev(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("APP_VERSION", raising=False)

    assert Settings().app_version == "dev"


def test_app_version_is_read_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    # CI sets APP_VERSION to the git SHA when it deploys.
    monkeypatch.setenv("APP_VERSION", "abc1234")

    assert Settings().app_version == "abc1234"
