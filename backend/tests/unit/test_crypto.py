"""Token encryption."""

import pytest

from tefteri.security.crypto import DecryptionError, TokenCipher


def test_roundtrip_and_not_plaintext() -> None:
    c = TokenCipher("secret-key-0123456789")
    token = c.encrypt("api-token")
    assert "api-token" not in token
    assert c.decrypt(token) == "api-token"


def test_wrong_key_fails() -> None:
    token = TokenCipher("secret-key-0123456789").encrypt("x")
    with pytest.raises(DecryptionError):
        TokenCipher("another-key-0123456789").decrypt(token)
