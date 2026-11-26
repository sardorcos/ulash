#!/usr/bin/env python3
"""Detach the iOS Share Extension from the Runner build for one CI build.

The Share Extension needs the App Group `group.uz.ulash.app` to be registered
in Apple Developer and assigned to both bundle IDs. Until that is done, signing
fails. With SHARE_EXTENSION=false the build ships without the extension:

  python3 scripts/ios_share_extension.py --disable [apps/file_transfer/ios]

This removes (in the working copy only):
  * the "Embed Foundation Extensions" phase from the Runner target,
  * Runner's dependency on the ShareExtension target,
  * the ShareExtension target from the project's target list,
  * the App Group entitlement from Runner.entitlements.
The script is idempotent and never touches signing settings or other targets.
"""
from __future__ import annotations

import argparse
import plistlib
import re
import sys
from pathlib import Path


def disable(ios: Path) -> None:
    pbx = ios / "Runner.xcodeproj" / "project.pbxproj"
    text = pbx.read_text(encoding="utf-8")

    target = re.search(r"^\t\t([0-9A-F]{24}) /\* ShareExtension \*/ = \{\n\t\t\tisa = PBXNativeTarget;",
                       text, re.M)
    if not target:
        print("ShareExtension target not found; nothing to do.")
    else:
        target_id = target.group(1)
        dependency = re.search(
            r"^\t\t([0-9A-F]{24}) /\* PBXTargetDependency \*/ = \{\n\t\t\tisa = PBXTargetDependency;\n"
            rf"\t\t\ttarget = {target_id} ",
            text, re.M)
        embed = re.search(r"^\t\t([0-9A-F]{24}) /\* Embed Foundation Extensions \*/ = \{", text, re.M)
        removed = 0
        patterns = [rf"^\t\t\t\t{target_id} /\* ShareExtension \*/,\n"]
        if dependency:
            patterns.append(rf"^\t\t\t\t{dependency.group(1)} /\* PBXTargetDependency \*/,\n")
        if embed:
            patterns.append(rf"^\t\t\t\t{embed.group(1)} /\* Embed Foundation Extensions \*/,\n")
        for pattern in patterns:
            text, count = re.subn(pattern, "", text, flags=re.M)
            removed += count
        pbx.write_text(text, encoding="utf-8")
        print(f"Detached ShareExtension from the Runner build ({removed} references).")

    entitlements = ios / "Runner" / "Runner.entitlements"
    data = plistlib.loads(entitlements.read_bytes())
    if data.pop("com.apple.security.application-groups", None) is not None:
        entitlements.write_bytes(plistlib.dumps(data))
        print("Removed the App Group entitlement from Runner.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--disable", action="store_true", required=True)
    parser.add_argument("ios", nargs="?", default="apps/file_transfer/ios")
    args = parser.parse_args()
    ios = Path(args.ios)
    if not (ios / "Runner.xcodeproj").is_dir():
        print(f"Not an iOS project directory: {ios}", file=sys.stderr)
        return 2
    disable(ios)
    return 0


if __name__ == "__main__":
    sys.exit(main())
