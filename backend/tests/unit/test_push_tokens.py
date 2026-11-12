"""The push token helper (spec 006, R-07)."""

from tefteri.security.tokens import digest_token, new_push_token, token_hint


def test_a_push_token_has_the_prefix_and_enough_randomness() -> None:
    token = new_push_token()

    assert token.startswith("tfv_")
    assert len(token) - len("tfv_") >= 43
    assert new_push_token() != token


def test_the_digest_is_stable_and_is_not_the_token() -> None:
    token = new_push_token()

    assert digest_token(token) == digest_token(token)
    assert digest_token(token) != token
    assert len(digest_token(token)) == 64


def test_the_hint_is_the_last_four_characters() -> None:
    assert token_hint("tfv_abcdefgh") == "efgh"


def test_sessions_and_push_tokens_share_one_digest() -> None:
    from tefteri.auth import service

    assert service._digest is digest_token  # type: ignore[attr-defined]
