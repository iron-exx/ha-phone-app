"""Standalone dev test-trigger CLI: sign and send one test push.

Sends a signed push-event envelope (see envelope.py) toward either a real
iOS device (APNs VoIP push, via aioapns) or a real Android device (FCM
data-only high-priority push, via firebase-admin), then logs the send
attempt locally.

Per D-04/D-05: this script lives standalone in the ha-phone-app repo and
never touches HA-Phone (Asterisk/FastAPI/AMI/ARI) -- it sends the push
directly to APNs/FCM to prove the platform push-wakeup path works before
any real PBX call flow exists.

Per D-08: this file makes exactly one send attempt per invocation and has
no timeout/backoff/repeat-on-failure behavior. Failures are logged, not
resent automatically; that hardening work is deferred to Phase 4/5.
"""

import argparse
import asyncio
import csv
import os
from datetime import datetime, timedelta, timezone

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from envelope import build_envelope, sign_envelope

DEFAULT_PRIVATE_KEY_PATH = "tools/keys/dev_private.hex"
LOG_PATH = "tools/logs/push_log.csv"
LOG_HEADER = [
    "sent_at_iso",
    "platform",
    "state",
    "event_id",
    "call_id",
    "issued_at",
    "expires_at",
    "result",
]


def _load_private_key(private_key_hex: str | None) -> Ed25519PrivateKey:
    """Load the dev Ed25519 private key from a hex string or the default file."""
    if private_key_hex is None:
        with open(DEFAULT_PRIVATE_KEY_PATH) as f:
            private_key_hex = f.read().strip()
    return Ed25519PrivateKey.from_private_bytes(bytes.fromhex(private_key_hex))


def send_ios_voip_push(
    device_token: str,
    envelope: dict,
    apns_key_path: str,
    apns_key_id: str | None,
    apns_team_id: str | None,
    apns_bundle_id: str,
    use_sandbox: bool,
) -> dict:
    """Send a single VoIP push via APNs using the signed envelope as payload.

    Exactly one send attempt, no timeout/backoff/repeat behavior (D-08).
    Returns a dict describing the outcome (never raises past this
    function so the caller can always log a result row).
    """
    from aioapns import APNs, NotificationRequest, PushType

    async def _send() -> dict:
        with open(apns_key_path) as f:
            key = f.read()

        client = APNs(
            key=key,
            key_id=apns_key_id,
            team_id=apns_team_id,
            topic=f"{apns_bundle_id}.voip",
            use_sandbox=use_sandbox,
        )
        request = NotificationRequest(
            device_token=device_token,
            message=envelope,
            push_type=PushType.VOIP,
            priority=10,
            topic=f"{apns_bundle_id}.voip",
        )
        response = await client.send_notification(request)
        return {"is_successful": response.is_successful, "status": response.status}

    try:
        return asyncio.run(_send())
    except Exception as exc:  # noqa: BLE001 - single attempt, log and move on (D-08)
        return {"is_successful": False, "error": str(exc)}


def send_android_fcm_push(
    fcm_token: str,
    envelope: dict,
    credentials_path: str,
) -> str:
    """Send a single data-only, high-priority push via FCM.

    Exactly one send attempt, no timeout/backoff/repeat behavior (D-08).
    Returns the FCM message ID on success, or an "error: ..." string on
    failure (never raises past this function).
    """
    import firebase_admin
    from firebase_admin import credentials, messaging

    try:
        if not firebase_admin._apps:
            cred = credentials.Certificate(credentials_path)
            firebase_admin.initialize_app(cred)

        message = messaging.Message(
            data={k: str(v) for k, v in envelope.items()},
            android=messaging.AndroidConfig(
                priority="high",
                ttl=timedelta(seconds=30),
            ),
            token=fcm_token,
        )
        return messaging.send(message)
    except Exception as exc:  # noqa: BLE001 - single attempt, log and move on (D-08)
        return f"error: {exc}"


def log_send(platform: str, state: str, envelope: dict, result) -> None:
    """Append a row describing this send attempt to tools/logs/push_log.csv."""
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    write_header = not os.path.exists(LOG_PATH)

    with open(LOG_PATH, mode="a", newline="") as f:
        writer = csv.writer(f)
        if write_header:
            writer.writerow(LOG_HEADER)
        writer.writerow(
            [
                datetime.now(timezone.utc).isoformat(),
                platform,
                state,
                envelope["event_id"],
                envelope["call_id"],
                envelope["issued_at"],
                envelope["expires_at"],
                result,
            ]
        )


def main() -> None:
    parser = argparse.ArgumentParser(prog="push_trigger.py")
    parser.add_argument("--platform", choices=["ios", "android"], required=True)
    parser.add_argument(
        "--state",
        required=True,
        help=(
            "app-state label for the log: "
            "foreground|backgrounded|locked|terminated|overnight"
        ),
    )
    parser.add_argument(
        "--device-token",
        required=True,
        help="APNs device token (iOS) or FCM registration token (Android)",
    )
    parser.add_argument(
        "--private-key-hex",
        default=None,
        help="dev Ed25519 private key hex; defaults to reading tools/keys/dev_private.hex",
    )
    parser.add_argument("--apns-key-path", default="tools/keys/AuthKey.p8")
    parser.add_argument("--apns-key-id", default=os.environ.get("APNS_KEY_ID"))
    parser.add_argument("--apns-team-id", default=os.environ.get("APPLE_TEAM_ID"))
    parser.add_argument(
        "--apns-bundle-id",
        default=os.environ.get("APNS_BUNDLE_ID", "de.systemwerk.haphone.test"),
    )
    parser.add_argument(
        "--fcm-credentials",
        default=os.environ.get(
            "FCM_CREDENTIALS_PATH", "tools/keys/firebase-service-account.json"
        ),
    )
    parser.add_argument(
        "--use-sandbox",
        action="store_true",
        default=True,
        help="APNs sandbox environment (dev builds)",
    )
    args = parser.parse_args()

    private_key = _load_private_key(args.private_key_hex)
    envelope = build_envelope()
    signed = sign_envelope(envelope, private_key)

    print(f"Envelope: {signed}")

    if args.platform == "ios":
        result = send_ios_voip_push(
            device_token=args.device_token,
            envelope=signed,
            apns_key_path=args.apns_key_path,
            apns_key_id=args.apns_key_id,
            apns_team_id=args.apns_team_id,
            apns_bundle_id=args.apns_bundle_id,
            use_sandbox=args.use_sandbox,
        )
    else:
        result = send_android_fcm_push(
            fcm_token=args.device_token,
            envelope=signed,
            credentials_path=args.fcm_credentials,
        )

    print(f"Result: {result}")

    log_send(args.platform, args.state, signed, result)
    print(f"Logged send attempt to {LOG_PATH}")


if __name__ == "__main__":
    main()
