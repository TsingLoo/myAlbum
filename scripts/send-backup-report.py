#!/usr/bin/env python3
import datetime
import hashlib
import hmac
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

CONFIG = Path("/home/ashton/.config/homeoss/tencent-ses.env")
ENDPOINT = "ses.tencentcloudapi.com"
SERVICE = "ses"
ACTION = "SendEmail"
VERSION = "2020-10-02"
ALGORITHM = "TC3-HMAC-SHA256"


def load_config(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator:
            raise ValueError(f"Invalid configuration line: {raw_line}")
        values[key.strip()] = value.strip()
    return values


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sign(key: bytes, message: str) -> bytes:
    return hmac.new(key, message.encode(), hashlib.sha256).digest()


def authorization(
    secret_id: str,
    secret_key: str,
    timestamp: int,
    payload: bytes,
) -> str:
    date = datetime.datetime.fromtimestamp(
        timestamp, datetime.UTC
    ).strftime("%Y-%m-%d")
    canonical_headers = (
        "content-type:application/json; charset=utf-8\n"
        f"host:{ENDPOINT}\n"
        f"x-tc-action:{ACTION.lower()}\n"
    )
    signed_headers = "content-type;host;x-tc-action"
    canonical_request = "\n".join(
        [
            "POST",
            "/",
            "",
            canonical_headers,
            signed_headers,
            sha256(payload),
        ]
    )
    credential_scope = f"{date}/{SERVICE}/tc3_request"
    string_to_sign = "\n".join(
        [
            ALGORITHM,
            str(timestamp),
            credential_scope,
            sha256(canonical_request.encode()),
        ]
    )
    secret_date = sign(("TC3" + secret_key).encode(), date)
    secret_service = sign(secret_date, SERVICE)
    secret_signing = sign(secret_service, "tc3_request")
    signature = hmac.new(
        secret_signing, string_to_sign.encode(), hashlib.sha256
    ).hexdigest()
    return (
        f"{ALGORITHM} Credential={secret_id}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )


def send_message(config: dict[str, str], subject: str, body: str) -> None:
    payload = json.dumps(
        {
            "FromEmailAddress": config["TENCENT_SES_FROM"],
            "Destination": [config["TENCENT_SES_TO"]],
            "Subject": subject,
            "Template": {
                "TemplateID": int(config["TENCENT_SES_TEMPLATE_ID"]),
                "TemplateData": json.dumps(
                    {"report": body}, ensure_ascii=False
                ),
            },
            "Unsubscribe": "0",
            "TriggerType": 0,
        },
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode()
    timestamp = int(time.time())
    headers = {
        "Authorization": authorization(
            config["TENCENT_SECRET_ID"],
            config["TENCENT_SECRET_KEY"],
            timestamp,
            payload,
        ),
        "Content-Type": "application/json; charset=utf-8",
        "Host": ENDPOINT,
        "X-TC-Action": ACTION,
        "X-TC-Version": VERSION,
        "X-TC-Timestamp": str(timestamp),
        "X-TC-Region": config["TENCENT_REGION"],
    }
    request = urllib.request.Request(
        f"https://{ENDPOINT}", data=payload, headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        details = error.read().decode(errors="replace")
        raise RuntimeError(
            f"Tencent SES HTTP error {error.code}: {details}"
        ) from error
    api_response = result.get("Response", {})
    if api_response.get("Error"):
        raise RuntimeError(
            "Tencent SES API error: "
            + json.dumps(api_response["Error"], ensure_ascii=False)
        )
    if not api_response.get("MessageId"):
        raise RuntimeError(
            "Tencent SES returned no MessageId: "
            + json.dumps(result, ensure_ascii=False)
        )
    print(
        f"Tencent SES accepted message {api_response['MessageId']}",
        flush=True,
    )


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} SUBJECT")
    config = load_config(CONFIG)
    required = (
        "TENCENT_SECRET_ID",
        "TENCENT_SECRET_KEY",
        "TENCENT_REGION",
        "TENCENT_SES_FROM",
        "TENCENT_SES_TO",
        "TENCENT_SES_TEMPLATE_ID",
    )
    missing = [key for key in required if not config.get(key)]
    if missing:
        raise SystemExit("Missing configuration: " + ", ".join(missing))
    send_message(config, sys.argv[1], sys.stdin.read())


if __name__ == "__main__":
    main()
