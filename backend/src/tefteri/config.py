"""Application settings read from ``TEFTERI_*`` environment variables."""

from pathlib import Path

from argon2 import extract_parameters
from argon2.exceptions import InvalidHashError
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration. Raw passwords are never accepted, only Argon2 hashes."""

    model_config = SettingsConfigDict(env_prefix="TEFTERI_", env_file=".env", extra="ignore")

    create_schema: bool = False
    database_url: str = "sqlite+aiosqlite:///./tefteri.db"
    admin_username: str = "admin"
    admin_password_hash: str
    secret_key: str = Field(min_length=16)

    web_dir: Path | None = None  # built web client (`flutter build web`), served at /
    public_url: str | None = None  # base URL for OAuth redirect addresses behind a proxy
    google_client_id: str | None = None
    google_client_secret: str | None = None

    sync_interval_minutes: int = Field(default=60, ge=0)
    """Minutes between two automatic syncs of all connections. 0 turns them off."""

    login_max_failures: int = 5
    login_window_seconds: int = 15 * 60
    login_block_seconds: int = 15 * 60
    session_lifetime_seconds: int = 8 * 60 * 60

    @field_validator("admin_password_hash")
    @classmethod
    def _must_be_argon2(cls, value: str) -> str:
        """Reject anything that is not a valid Argon2 hash (e.g. a raw password)."""
        try:
            extract_parameters(value)
        except InvalidHashError as exc:
            raise ValueError(
                "admin_password_hash must be an Argon2 hash (generate with `just hash-password`)"
            ) from exc
        return value
