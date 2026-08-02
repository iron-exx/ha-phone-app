"""Generate a dev Ed25519 keypair for signing push-event envelopes.

Single dev signing key for Phase 1 (per D-07 scope) -- no key distribution
mechanism needed yet. Writes the raw private/public key bytes as hex to
disk (gitignored, see .gitignore) and prints the public key so it can be
pasted into the iOS/Android app's hardcoded verifier constant.

Usage:
    python tools/keygen.py --out tools/keys/dev
"""

import argparse
import base64
import os

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def generate_keypair() -> tuple[bytes, bytes]:
    """Generate a fresh Ed25519 keypair, returned as (private, public) raw bytes."""
    private_key = Ed25519PrivateKey.generate()
    public_key = private_key.public_key()

    private_bytes = private_key.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_bytes = public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return private_bytes, public_bytes


def main() -> None:
    parser = argparse.ArgumentParser(prog="keygen.py")
    parser.add_argument(
        "--out",
        default="tools/keys/dev",
        help="output path prefix; writes {out}_private.hex and {out}_public.hex",
    )
    args = parser.parse_args()

    private_bytes, public_bytes = generate_keypair()

    out_dir = os.path.dirname(args.out) or "."
    os.makedirs(out_dir, exist_ok=True)

    private_path = f"{args.out}_private.hex"
    public_path = f"{args.out}_public.hex"

    with open(private_path, "w") as f:
        f.write(private_bytes.hex())
    with open(public_path, "w") as f:
        f.write(public_bytes.hex())

    print(f"Wrote private key to {private_path} (never commit this file)")
    print(f"Wrote public key to {public_path}")
    print(f"Public key (hex):    {public_bytes.hex()}")
    print(f"Public key (base64): {base64.b64encode(public_bytes).decode()}")
    print(
        "Paste the public key above into the iOS/Android app's hardcoded "
        "dev verifier constant."
    )


if __name__ == "__main__":
    main()
