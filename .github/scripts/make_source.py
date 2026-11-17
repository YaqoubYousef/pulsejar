"""Write a SideStore/AltStore source (apps.json) pointing at this build's release.

Usage: python3 make_source.py <path-to-ipa> <output-json>
Reads APP_VERSION, BUILD_NUMBER, RELEASE_TAG and GitHub's own env vars.
"""

import json
import os
import sys
from datetime import datetime, timezone

ipa_path, out_path = sys.argv[1], sys.argv[2]

repo = os.environ["GITHUB_REPOSITORY"]  # e.g. owner/pulsejar
owner = repo.split("/")[0]
tag = os.environ["RELEASE_TAG"]
version = os.environ["APP_VERSION"]
build = os.environ["BUILD_NUMBER"]
sha = os.environ.get("GITHUB_SHA", "")[:7]

base = f"https://github.com/{repo}"
raw = f"https://raw.githubusercontent.com/{repo}/main"

source = {
    "name": "PulseJar",
    "identifier": "com.personal.pulsejar.source",
    "sourceURL": f"{base}/releases/latest/download/apps.json",
    "website": base,
    "apps": [
        {
            "name": "PulseJar",
            "bundleIdentifier": "com.personal.pulsejar",
            "developerName": owner,
            "subtitle": "Personal finance, on your phone",
            "localizedDescription": (
                "A personal iPhone finance app. Accounts, categories, debts and "
                "bank SMS ingest. All data stays on the phone."
            ),
            "iconURL": f"{raw}/PulseJar/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
            "tintColor": "#C8643B",
            "versions": [
                {
                    "version": version,
                    "buildVersion": build,
                    "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "localizedDescription": f"Build {build} ({sha}).",
                    "downloadURL": f"{base}/releases/download/{tag}/PulseJar.ipa",
                    "size": os.path.getsize(ipa_path),
                    "minOSVersion": "17.0",
                }
            ],
            # Legacy top-level fields, read by older SideStore/AltStore versions.
            "version": version,
            "versionDate": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            "downloadURL": f"{base}/releases/download/{tag}/PulseJar.ipa",
            "size": os.path.getsize(ipa_path),
        }
    ],
    "news": [],
}

with open(out_path, "w") as f:
    json.dump(source, f, indent=2)

print(f"Wrote {out_path} for {version} ({tag})")
