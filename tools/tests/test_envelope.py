"""Tests for the signed push-event envelope contract (tools/envelope.py).

Covers roundtrip sign/verify, tamper rejection, expiry detection, and a
golden cross-language fixture that iOS (Swift/CryptoKit) and Android
(Kotlin/Tink or BouncyCastle) test suites must match byte-for-byte.
"""

import base64

from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

from envelope import (
    build_envelope,
    canonical_bytes,
    is_expired,
    sign_envelope,
    verify_envelope,
)

# Golden fixture values -- copied verbatim from 01-01-PLAN.md <interfaces> block.
# Swift/Kotlin test suites in later plans MUST reuse these same values.
PRIVATE_KEY_HEX = "0101010101010101010101010101010101010101010101010101010101010101"
PUBLIC_KEY_HEX = "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c"
FIXTURE_ENVELOPE = {
    "call_id": "11111111-1111-1111-1111-111111111111",
    "call_type": "audio",
    "caller": "HA-Phone Testanruf",
    "event_id": "22222222-2222-2222-2222-222222222222",
    "expires_at": 1700000030,
    "issued_at": 1700000000,
    "v": 1,
}
EXPECTED_CANONICAL_BYTES = (
    b'{"call_id":"11111111-1111-1111-1111-111111111111",'
    b'"call_type":"audio","caller":"HA-Phone Testanruf",'
    b'"event_id":"22222222-2222-2222-2222-222222222222",'
    b'"expires_at":1700000030,"issued_at":1700000000,"v":1}'
)
SIG_HEX = (
    "3a42bdf223211578e8ff6211a9c91ec6509d25f8f6750a384ff08ca1e751bf0"
    "3867d30ac1ab0377ade27c6f4af94c01cb6cfa28e7e9b5bdd467b7fa07089ff04"
)


def test_roundtrip_sign_and_verify():
    private_key = Ed25519PrivateKey.generate()
    public_key = private_key.public_key()

    envelope = build_envelope()
    signed = sign_envelope(envelope, private_key)

    assert verify_envelope(signed, public_key) is True


def test_tampered_envelope_fails_verification():
    private_key = Ed25519PrivateKey.generate()
    public_key = private_key.public_key()

    envelope = build_envelope()
    signed = sign_envelope(envelope, private_key)

    tampered = dict(signed)
    tampered["caller"] = tampered["caller"] + "X"

    assert verify_envelope(tampered, public_key) is False


def test_is_expired_true_for_past_and_false_for_future_timestamp():
    envelope = build_envelope(ttl_seconds=30)

    future_now = envelope["expires_at"] + 1
    assert is_expired(envelope, now=future_now) is True

    past_now = envelope["expires_at"] - 1
    assert is_expired(envelope, now=past_now) is False


def test_golden_canonical_bytes_match_fixture():
    assert canonical_bytes(FIXTURE_ENVELOPE) == EXPECTED_CANONICAL_BYTES
    assert len(EXPECTED_CANONICAL_BYTES) == 203


def test_golden_signature_verifies_with_fixed_keypair():
    private_key_bytes = bytes.fromhex(PRIVATE_KEY_HEX)
    private_key = Ed25519PrivateKey.from_private_bytes(private_key_bytes)

    signed = sign_envelope(FIXTURE_ENVELOPE, private_key)
    sig_bytes = base64.b64decode(signed["sig"])

    assert sig_bytes.hex() == SIG_HEX

    public_key_bytes = bytes.fromhex(PUBLIC_KEY_HEX)
    public_key = Ed25519PublicKey.from_public_bytes(public_key_bytes)

    fixture_with_sig = dict(FIXTURE_ENVELOPE)
    fixture_with_sig["sig"] = base64.b64encode(bytes.fromhex(SIG_HEX)).decode()

    assert verify_envelope(fixture_with_sig, public_key) is True
