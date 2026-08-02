"""Signed push-event envelope contract.

Defines the minimal, signed JSON envelope sent from a HA-Phone box (or, in
Phase 1, the standalone dev test-trigger script) to a mobile device via
APNs (VoIP push) or FCM (data-only high-priority push) to wake the app into
native call UI.

The payload is signed from the start (per decision D-07) so this contract
survives unchanged into the Phase 6 multi-tenant push-relay -- signing is
not bolted on retroactively.

Canonicalization contract (must be replicated byte-for-byte by the Swift
and Kotlin verifiers built in later plans):
    - Only the fields in CANONICAL_FIELD_ORDER are ever serialized (the
      `sig` field, if present, is always excluded).
    - JSON keys are sorted alphabetically, no whitespace
      (`separators=(",", ":")`).
    - Encoded as UTF-8 bytes before signing/verifying.
"""

import time
import uuid
import json
import base64

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

CANONICAL_FIELD_ORDER = [
    "call_id",
    "call_type",
    "caller",
    "event_id",
    "expires_at",
    "issued_at",
    "v",
]


def build_envelope(
    call_type: str = "audio",
    caller: str = "HA-Phone Testanruf",
    ttl_seconds: int = 30,
) -> dict:
    """Build a new, unsigned push-event envelope.

    Generates fresh `event_id`/`call_id` UUIDs and timestamps based on the
    current time. `v` is the envelope schema version (currently 1).
    """
    issued_at = int(time.time())
    return {
        "call_id": str(uuid.uuid4()),
        "call_type": call_type,
        "caller": caller,
        "event_id": str(uuid.uuid4()),
        "expires_at": issued_at + ttl_seconds,
        "issued_at": issued_at,
        "v": 1,
    }


def canonical_bytes(envelope: dict) -> bytes:
    """Serialize an envelope to its canonical signing/verification bytes.

    Only the CANONICAL_FIELD_ORDER keys are ever included -- `sig` (if
    present in the input dict) is always excluded, since it can't sign
    itself. Keys are sorted alphabetically with no whitespace, so this
    output is stable across platforms/languages given the same field
    values.
    """
    ordered = {k: envelope[k] for k in CANONICAL_FIELD_ORDER}
    return json.dumps(ordered, sort_keys=True, separators=(",", ":")).encode(
        "utf-8"
    )


def sign_envelope(envelope: dict, private_key: Ed25519PrivateKey) -> dict:
    """Return a NEW dict: envelope plus a base64-encoded `sig` field.

    Never mutates the input dict (immutability per project coding-style
    rule) -- the caller's original envelope object is left untouched.
    """
    signature = private_key.sign(canonical_bytes(envelope))
    return {**envelope, "sig": base64.b64encode(signature).decode("ascii")}


def verify_envelope(envelope: dict, public_key: Ed25519PublicKey) -> bool:
    """Verify an envelope's `sig` field against its canonical bytes.

    Returns a bool -- never raises -- so callers can't accidentally skip
    the check via an uncaught exception. Any malformed/missing signature,
    tampered field, or verification failure results in False.
    """
    try:
        sig_b64 = envelope["sig"]
        signature = base64.b64decode(sig_b64)
        public_key.verify(signature, canonical_bytes(envelope))
        return True
    except (InvalidSignature, KeyError, ValueError, TypeError):
        return False


def is_expired(envelope: dict, now: float | None = None) -> bool:
    """Return True if the envelope's `expires_at` timestamp has passed.

    `now` is injectable for testability (defaults to `time.time()`).
    """
    current = now if now is not None else time.time()
    return current > envelope["expires_at"]
