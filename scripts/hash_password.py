"""Prompt for a password and print its Argon2 hash (for TEFTERI_ADMIN_PASSWORD_HASH)."""

import getpass
import sys

from tefteri.auth.passwords import hash_password


def main() -> int:
    """Read a password twice and print its hash."""
    first = getpass.getpass("Password: ")
    if first != getpass.getpass("Repeat: "):
        print("Passwords differ", file=sys.stderr)
        return 1
    if not first:
        print("Empty password", file=sys.stderr)
        return 1
    print(hash_password(first))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
