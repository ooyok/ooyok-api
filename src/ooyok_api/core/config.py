# App configuration, read from environment variables and validated by type at startup.
from pydantic_settings import BaseSettings


# Why base Settings on BaseSettings
# - Automatic field type conversion (os.environ values are always strings)
# - Reads real environment variables; a .env file is read only if enabled with
#   model_config = SettingsConfigDict(env_file=".env"), and real env vars override it
# - Default values for fields
class Settings(BaseSettings):
    # Each field maps to an env var of the same name, case-insensitive: app_version ← APP_VERSION.
    # A missing or badly typed value fails at startup instead of mid-request.

    # Git SHA of the running build; CI sets it on deploy. "dev" means a local run.
    app_version: str = "dev"
