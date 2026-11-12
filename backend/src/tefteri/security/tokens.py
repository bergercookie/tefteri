"""Token helpers: random tokens and their stored digests (spec 006).

A push token is shown once and only its digest is stored, the same way as a session token
(``auth.service``). Both share ``digest_token`` so the two never drift apart.
"""

import hashlib
import secrets


def new_push_token() -> str:
    """Return a fresh push token: ``tfv_`` plus 32 random bytes, URL-safe base64."""
    return f"tfv_{secrets.token_urlsafe(32)}"


def digest_token(token: str) -> str:
    """Return the SHA-256 hex digest of a token. Only this is stored."""
    return hashlib.sha256(token.encode()).hexdigest()


def token_hint(token: str) -> str:
    """Return the last four characters of a token, for the settings screen."""
    return token[-4:]
