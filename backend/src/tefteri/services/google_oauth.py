"""Google OAuth2 authorization-code flow for connecting a Google account."""

import uuid
from typing import Any
from urllib.parse import urlencode

import httpx
from itsdangerous import BadSignature, URLSafeTimedSerializer

from tefteri.domain.errors import AuthExpired, BackendUnavailable

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"  # noqa: S105
SCOPE = "https://www.googleapis.com/auth/calendar"
STATE_MAX_AGE = 600


class InvalidState(Exception):
    """The OAuth ``state`` value is missing, forged or expired."""


class GoogleOAuth:
    """Builds authorization URLs and exchanges codes for refresh tokens."""

    def __init__(
        self, client: httpx.AsyncClient, client_id: str, client_secret: str, secret_key: str
    ) -> None:
        """Use the Google app credentials and the app secret to sign ``state``."""
        self._client = client
        self._client_id = client_id
        self._client_secret = client_secret
        self._signer = URLSafeTimedSerializer(secret_key, salt="google-oauth")

    def authorize_url(self, user_id: uuid.UUID, redirect_uri: str, extra: dict[str, Any]) -> str:
        """Return the Google consent URL. ``extra`` (the name) travels in signed state."""
        state = self._signer.dumps({"user_id": str(user_id), **extra})
        query = urlencode(
            {
                "client_id": self._client_id,
                "redirect_uri": redirect_uri,
                "response_type": "code",
                "scope": SCOPE,
                "access_type": "offline",
                "prompt": "consent",
                "state": state,
            }
        )
        return f"{AUTH_URL}?{query}"

    def read_state(self, state: str) -> dict[str, Any]:
        """Validate ``state`` and return its payload."""
        try:
            data: dict[str, Any] = self._signer.loads(state, max_age=STATE_MAX_AGE)
        except BadSignature as exc:
            raise InvalidState from exc
        return data

    async def exchange_code(self, code: str, redirect_uri: str) -> str:
        """Exchange an authorization code for a refresh token."""
        try:
            response = await self._client.post(
                TOKEN_URL,
                data={
                    "grant_type": "authorization_code",
                    "code": code,
                    "redirect_uri": redirect_uri,
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                },
            )
        except httpx.TransportError as exc:
            raise BackendUnavailable("cannot reach Google") from exc
        if response.status_code >= 400 or "refresh_token" not in response.json():
            raise AuthExpired("Google did not grant offline access")
        return str(response.json()["refresh_token"])
