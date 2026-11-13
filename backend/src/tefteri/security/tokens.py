"""Token helpers: random tokens and their stored digests.

A token is shown once and only its digest is stored. The session service uses
``digest_token``.
"""

import hashlib


def digest_token(token: str) -> str:
    """Return the SHA-256 hex digest of a token. Only this is stored."""
    return hashlib.sha256(token.encode()).hexdigest()
