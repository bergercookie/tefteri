"""Token helpers: random tokens and their stored digests.

A token is shown once and only its digest is stored. The session service uses
``digest_token``.
"""

import hashlib

API_KEY_PREFIX = "tft_"
"""Every API key starts with this, so a key is told from a login session token at a glance."""


def digest_token(token: str) -> str:
    """Return the SHA-256 hex digest of a token. Only this is stored."""
    return hashlib.sha256(token.encode()).hexdigest()
