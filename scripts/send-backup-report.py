#!/usr/bin/env python3
import os
import smtplib
import ssl
import sys
from email.message import EmailMessage
from pathlib import Path

CONFIG = Path("/home/ashton/.config/homeoss/outlook-smtp.env")


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


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} SUBJECT")

    config = load_config(CONFIG)
    required = ("SMTP_HOST", "SMTP_PORT", "SMTP_USERNAME",
                "SMTP_APP_PASSWORD", "SMTP_FROM", "SMTP_TO")
    missing = [key for key in required if not config.get(key)]
    if missing:
        raise SystemExit(f"Missing mail settings: {', '.join(missing)}")

    message = EmailMessage()
    message["Subject"] = sys.argv[1]
    message["From"] = config["SMTP_FROM"]
    message["To"] = config["SMTP_TO"]
    message.set_content(sys.stdin.read())

    with smtplib.SMTP(
        config["SMTP_HOST"], int(config["SMTP_PORT"]), timeout=30
    ) as smtp:
        smtp.ehlo()
        smtp.starttls(context=ssl.create_default_context())
        smtp.ehlo()
        smtp.login(config["SMTP_USERNAME"], config["SMTP_APP_PASSWORD"])
        smtp.send_message(message)


if __name__ == "__main__":
    main()
