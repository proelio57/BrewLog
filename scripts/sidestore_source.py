#!/usr/bin/env python3
"""Creates or updates the SideStore/AltStore source (source.json) for a new BrewLog release.

Usage: sidestore_source.py SOURCE_JSON --version 1.0.12 --build 12 --ipa BrewLog.ipa \
           --download-url URL --source-url URL --icon-url URL [--notes TEXT]
Keeps the newest 10 versions. Bundle id and Bluetooth text are read from Config/Base.xcconfig and project.yml.
"""
import argparse
import datetime
import json
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def setting(pattern, text, default):
    match = re.search(pattern, text, re.MULTILINE)
    return match.group(1).strip().strip('"') if match else default


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--ipa", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--source-url", required=True)
    parser.add_argument("--icon-url", required=True)
    parser.add_argument("--notes", default="")
    args = parser.parse_args()

    project = read("project.yml")
    bundle_id = setting(r"^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)", read("Config/Base.xcconfig"), "com.brewlog.app")
    min_os = setting(r"^\s+iOS:\s*(\S+)", project, "17.0")
    bluetooth = setting(r"INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription:\s*(.+)$", project,
                        "BrewLog connects to your Bluetooth coffee scale.")

    try:
        with open(args.source, encoding="utf-8") as f:
            source = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        source = {}

    old_app = (source.get("apps") or [{}])[0]
    versions = [v for v in old_app.get("versions", []) if v.get("version") != args.version]
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    notes = args.notes.strip()[:2000]
    size = os.path.getsize(args.ipa)
    version = {
        "version": args.version,
        "buildVersion": args.build,
        "date": now,
        "localizedDescription": notes,
        "downloadURL": args.download_url,
        "size": size,
        "minOSVersion": min_os,
    }
    versions = [version] + versions[:9]

    app = {
        "name": "BrewLog",
        "bundleIdentifier": bundle_id,
        "developerName": "BrewLog",
        "subtitle": "Pour-over brewing companion",
        "localizedDescription": "Live BOOKOO scale guidance, a brew journal and taste-based tips for your next cup.",
        "iconURL": args.icon_url,
        "tintColor": "#B86D3C",
        "category": "lifestyle",
        "versions": versions,
        "appPermissions": {
            "entitlements": [],
            "privacy": {"NSBluetoothAlwaysUsageDescription": bluetooth},
        },
        # Older SideStore/AltStore versions read the latest version from these fields.
        "version": args.version,
        "versionDate": now,
        "versionDescription": notes,
        "downloadURL": args.download_url,
        "size": size,
    }
    source = {
        "name": "BrewLog",
        "identifier": bundle_id + ".source",
        "sourceURL": args.source_url,
        "iconURL": args.icon_url,
        "tintColor": "#B86D3C",
        "apps": [app],
        "news": source.get("news", []),
    }
    with open(args.source, "w", encoding="utf-8") as f:
        json.dump(source, f, indent=2, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    main()
