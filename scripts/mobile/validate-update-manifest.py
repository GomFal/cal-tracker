#!/usr/bin/env python3
"""Validate the public direct-download manifest without fetching an APK."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import NoReturn
from urllib.parse import urlsplit


CHANNELS = {
    "dev": {
        "origin": "https://dev-api.bettercalories.app",
        "host": "dev-api.bettercalories.app",
        "package": "app.bettercalories.dev",
    },
    "prod": {
        "origin": "https://api.bettercalories.app",
        "host": "api.bettercalories.app",
        "package": "app.bettercalories",
    },
}
REQUIRED_KEYS = {
    "channel",
    "packageName",
    "versionName",
    "versionCode",
    "apkUrl",
    "sha256",
    "sizeBytes",
    "publishedAt",
}
APK_NAME = re.compile(r"^[A-Za-z0-9._-]+\.apk$")
SHA256 = re.compile(r"^[A-Fa-f0-9]{64}$")


def fail(message: str) -> NoReturn:
    print(f"Update manifest validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--channel", required=True, choices=sorted(CHANNELS))
    parser.add_argument("--minimum-version-code", type=int)
    parser.add_argument("--expected-version-code", type=int)
    parser.add_argument("--print-apk-url", action="store_true")
    parser.add_argument("--print-version-code", action="store_true")
    return parser.parse_args()


def load_manifest(path: Path) -> dict[str, object]:
    try:
        if path.stat().st_size > 64 * 1024:
            fail("document exceeds 64 KiB")
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("document is not readable UTF-8 JSON")
    if not isinstance(value, dict):
        fail("document root must be an object")
    return value


def validate(manifest: dict[str, object], args: argparse.Namespace) -> tuple[str, int]:
    if not REQUIRED_KEYS.issubset(manifest):
        fail("one or more required fields are missing")

    policy = CHANNELS[args.channel]
    if manifest["channel"] != args.channel:
        fail("channel does not match the publication target")
    if manifest["packageName"] != policy["package"]:
        fail("package does not match the publication target")

    version_name = manifest["versionName"]
    version_code = manifest["versionCode"]
    if not isinstance(version_name, str) or not version_name.strip():
        fail("versionName must be a non-empty string")
    if isinstance(version_code, bool) or not isinstance(version_code, int):
        fail("versionCode must be an integer")
    if version_code <= 0:
        fail("versionCode must be positive")
    if (
        args.minimum_version_code is not None
        and version_code <= args.minimum_version_code
    ):
        fail("versionCode does not strictly advance")
    if (
        args.expected_version_code is not None
        and version_code != args.expected_version_code
    ):
        fail("versionCode does not match the artifact being published")

    published_at = manifest["publishedAt"]
    if not isinstance(published_at, str):
        fail("publishedAt must be a UTC timestamp")
    try:
        parsed_time = datetime.fromisoformat(published_at.replace("Z", "+00:00"))
    except ValueError:
        fail("publishedAt must be a UTC timestamp")
    if parsed_time.utcoffset() is None or parsed_time.utcoffset().total_seconds() != 0:
        fail("publishedAt must be a UTC timestamp")

    apk_url = manifest["apkUrl"]
    if not isinstance(apk_url, str):
        fail("apkUrl must be a string")
    parsed_url = urlsplit(apk_url)
    try:
        explicit_port = parsed_url.port
    except ValueError:
        fail("apkUrl contains an invalid port")
    if (
        parsed_url.scheme != "https"
        or parsed_url.hostname != policy["host"]
        or explicit_port is not None
        or parsed_url.username is not None
        or parsed_url.password is not None
        or parsed_url.query
        or parsed_url.fragment
        or not parsed_url.path.startswith("/apk/")
        or "/" in parsed_url.path.removeprefix("/apk/")
        or not APK_NAME.fullmatch(parsed_url.path.removeprefix("/apk/"))
    ):
        fail("apkUrl is outside the exact approved HTTPS origin and APK path")

    sha256 = manifest["sha256"]
    if not isinstance(sha256, str) or not SHA256.fullmatch(sha256):
        fail("sha256 must be one hexadecimal SHA-256 digest")
    size_bytes = manifest["sizeBytes"]
    if (
        isinstance(size_bytes, bool)
        or not isinstance(size_bytes, int)
        or size_bytes <= 0
    ):
        fail("sizeBytes must be a positive integer")

    return apk_url, version_code


def main() -> None:
    args = parse_args()
    apk_url, version_code = validate(load_manifest(args.manifest), args)
    if args.print_apk_url:
        print(apk_url)
    if args.print_version_code:
        print(version_code)


if __name__ == "__main__":
    main()
