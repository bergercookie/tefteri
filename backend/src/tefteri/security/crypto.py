"""Encryption of third-party credentials at rest (Fernet)."""

import base64
import hashlib

from cryptography.fernet import Fernet, InvalidToken


class DecryptionError(Exception):
    """Raised when a stored secret cannot be decrypted."""


class TokenCipher:
    """Encrypt and decrypt short secrets with a key derived from the app secret."""

    def __init__(self, secret_key: str) -> None:
        """Derive a Fernet key from ``secret_key``."""
        digest = hashlib.sha256(secret_key.encode()).digest()
        self._fernet = Fernet(base64.urlsafe_b64encode(digest))

    def encrypt(self, plaintext: str) -> str:
        """Return the encrypted, URL-safe text form of ``plaintext``."""
        return self._fernet.encrypt(plaintext.encode()).decode()

    def decrypt(self, token: str) -> str:
        """Return the plaintext, or raise ``DecryptionError`` for a bad token or key."""
        try:
            return self._fernet.decrypt(token.encode()).decode()
        except InvalidToken as exc:
            raise DecryptionError("cannot decrypt stored credentials") from exc
