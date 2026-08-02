#!/usr/bin/env python3
import smtplib
import ssl
import sys
from email.message import EmailMessage
from pathlib import Path

CONFIG = Path("/home/ashton/.config/homeoss/healthchecks.env")


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


def enabled(value: str) -> bool:
    return value.lower() in {"1", "true", "yes", "on"}


def send_message(config: dict[str, str], subject: str, body: str) -> None:
    message = EmailMessage()
    message["From"] = config.get("DEFAULT_FROM_EMAIL", config["EMAIL_HOST_USER"])
    message["To"] = config["BACKUP_REPORT_TO"]
    message["Subject"] = subject
    message.set_content(body)

    host = config["EMAIL_HOST"]
    port = int(config["EMAIL_PORT"])
    context = ssl.create_default_context()
    if enabled(config.get("EMAIL_USE_SSL", "false")):
        smtp = smtplib.SMTP_SSL(host, port, timeout=30, context=context)
    else:
        smtp = smtplib.SMTP(host, port, timeout=30)

    with smtp:
        if enabled(config.get("EMAIL_USE_TLS", "false")):
            smtp.starttls(context=context)
        smtp.login(config["EMAIL_HOST_USER"], config["EMAIL_HOST_PASSWORD"])
        smtp.send_message(message)
    print("SMTP accepted backup report", flush=True)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} SUBJECT")
    config = load_config(CONFIG)
    required = (
        "EMAIL_HOST",
        "EMAIL_HOST_PASSWORD",
        "EMAIL_HOST_USER",
        "EMAIL_PORT",
        "BACKUP_REPORT_TO",
    )
    missing = [key for key in required if not config.get(key)]
    if missing:
        raise SystemExit("Missing configuration: " + ", ".join(missing))
    send_message(config, sys.argv[1], sys.stdin.read())


if __name__ == "__main__":
    main()
