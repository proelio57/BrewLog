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

SUBTITLE = "Pour-over and espresso brewing companion"
DESCRIPTION = (
    "Guides every brew, pour-over or espresso, and keeps a journal of it.\n\n"
    "• Bluetooth scales (BOOKOO, Timemore, Decent): live weight and flow, a ping just before the target weight, "
    "spoken step prompts and a live graph. Also on the Lock Screen and in the Dynamic Island.\n"
    "• Espresso machines (GaggiMate, Decent DE1, La Marzocco): follows the shot, stops it at the yield, shows "
    "pressure and temperature, and switches the machine and its smart plug off when you are done.\n"
    "• Recipes from the specialty scene, your own gear, beans (scan the bag) and grinder settings down to the click.\n"
    "• Taste feedback that tells you what to change next time, statistics, widgets and optional Git backup.\n\n"
    "No account, no analytics: your data stays on your iPhone."
)

PLATFORMS = ("ios", "android", "web")


def ios_notes(text):
    """The release notes for the iOS app: only what applies to iOS, as plain lines without platform headings.

    RELEASE_NOTES.md groups its lines by platform ("iOS", "Android", "Web", or shared headings such as
    "iOS & Android" and "All platforms"); this source is the iOS app, so Android and Web lines are left out, and
    so are "No changes" lines. Notes without such headings (commit subjects) are kept as they are.
    """
    heading = re.compile(r"(?i)^(all platforms|(ios|android|web)(\s*(&|,|and)\s*(ios|android|web))*)$")
    current = None
    lines = []
    grouped = False
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if heading.match(line):
            grouped = True
            current = set(PLATFORMS) if line.lower() == "all platforms" else set(re.findall(r"ios|android|web", line.lower()))
            continue
        if grouped and "ios" not in (current or set()):
            continue
        if re.match(r"(?i)^[•\-*]?\s*no (app )?changes\b", line):
            continue
        lines.append(line)
    return "\n".join(lines) or "Bug fixes and improvements."


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
    # Every usage description from project.yml, e.g. Bluetooth and local network.
    privacy = {key: text.strip().strip('"') for key, text in
               re.findall(r"INFOPLIST_KEY_(NS\w+UsageDescription):\s*(.+)$", project, re.MULTILINE)}

    try:
        with open(args.source, encoding="utf-8") as f:
            source = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        source = {}

    old_app = (source.get("apps") or [{}])[0]
    def key(text):
        return [int(part) if part.isdigit() else 0 for part in str(text).split(".")]

    # Drop the same version and any "newer" ones, e.g. after the numbering was reset from 1.0.x to 0.1.x.
    versions = [v for v in old_app.get("versions", []) if key(v.get("version", "0")) < key(args.version)]
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    notes = ios_notes(args.notes)[:2000]
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
        "subtitle": SUBTITLE,
        "localizedDescription": DESCRIPTION,
        "iconURL": args.icon_url,
        "tintColor": "#B86D3C",
        "category": "lifestyle",
        "versions": versions,
        "appPermissions": {
            "entitlements": [],
            "privacy": privacy,
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
