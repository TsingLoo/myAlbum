#!/usr/bin/env python3
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CONFIG = Path("/home/ashton/.config/homeoss/outlook-graph.env")
TOKEN_FILE = Path("/home/ashton/.config/homeoss/outlook-graph-token.json")
SCOPE = "https://graph.microsoft.com/Mail.Send offline_access"


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


def post_form(url: str, data: dict[str, str]) -> dict:
    request = urllib.request.Request(
        url,
        data=urllib.parse.urlencode(data).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        details = error.read().decode(errors="replace")
        raise RuntimeError(f"Microsoft identity error {error.code}: {details}") from error


def save_token(token: dict) -> None:
    TOKEN_FILE.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = TOKEN_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(token), encoding="utf-8")
    os.chmod(temporary, 0o600)
    temporary.replace(TOKEN_FILE)


def authorize(config: dict[str, str]) -> None:
    tenant = config.get("GRAPH_TENANT", "consumers")
    base = f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0"
    device = post_form(
        f"{base}/devicecode",
        {"client_id": config["GRAPH_CLIENT_ID"], "scope": SCOPE},
    )
    print(device["message"], flush=True)

    deadline = time.monotonic() + int(device["expires_in"])
    interval = int(device.get("interval", 5))
    while time.monotonic() < deadline:
        time.sleep(interval)
        try:
            token = post_form(
                f"{base}/token",
                {
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "client_id": config["GRAPH_CLIENT_ID"],
                    "device_code": device["device_code"],
                },
            )
        except RuntimeError as error:
            if "authorization_pending" in str(error):
                continue
            if "slow_down" in str(error):
                interval += 5
                continue
            raise
        save_token(token)
        print("Microsoft Graph authorization completed.")
        return
    raise TimeoutError("Device authorization expired")


def refresh_access_token(config: dict[str, str]) -> str:
    if not TOKEN_FILE.exists():
        raise RuntimeError(f"Run {sys.argv[0]} --authorize first")
    current = json.loads(TOKEN_FILE.read_text(encoding="utf-8"))
    refresh_token = current.get("refresh_token")
    if not refresh_token:
        raise RuntimeError("Stored token has no refresh_token; authorize again")

    tenant = config.get("GRAPH_TENANT", "consumers")
    token = post_form(
        f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token",
        {
            "client_id": config["GRAPH_CLIENT_ID"],
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "scope": SCOPE,
        },
    )
    save_token(token)
    return token["access_token"]


def send_message(config: dict[str, str], subject: str, body: str) -> None:
    access_token = refresh_access_token(config)
    payload = {
        "message": {
            "subject": subject,
            "body": {"contentType": "Text", "content": body},
            "toRecipients": [
                {"emailAddress": {"address": config["GRAPH_TO"]}}
            ],
        },
        "saveToSentItems": True,
    }
    request = urllib.request.Request(
        "https://graph.microsoft.com/v1.0/me/sendMail",
        data=json.dumps(payload).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 202:
                raise RuntimeError(f"Unexpected Graph status: {response.status}")
    except urllib.error.HTTPError as error:
        details = error.read().decode(errors="replace")
        raise RuntimeError(f"Graph sendMail error {error.code}: {details}") from error


def main() -> None:
    config = load_config(CONFIG)
    if not config.get("GRAPH_CLIENT_ID"):
        raise SystemExit("GRAPH_CLIENT_ID is missing")
    if sys.argv[1:] == ["--authorize"]:
        authorize(config)
        return
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} SUBJECT | --authorize")
    if not config.get("GRAPH_TO"):
        raise SystemExit("GRAPH_TO is missing")
    send_message(config, sys.argv[1], sys.stdin.read())


if __name__ == "__main__":
    main()
