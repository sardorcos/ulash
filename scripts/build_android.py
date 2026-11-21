#!/usr/bin/env python3
"""Build the Android app, preserving inherited network policy and TLS checks.

Java/Gradle do not automatically consume HTTP(S)_PROXY in every environment.
This helper translates the currently inherited endpoints into JVM properties
for this build only. It never writes proxy settings or credentials to the repo.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urlsplit


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter", help="Flutter executable; defaults to PATH")
    parser.add_argument("--android-sdk", type=Path)
    parser.add_argument("--java-home", type=Path, help="Full JDK home containing bin/java and bin/javac")
    parser.add_argument("--gradle-user-home", type=Path)
    parser.add_argument("--mode", choices=("debug", "release"), default="debug")
    parser.add_argument("--target-platform", help="For example android-arm64")
    parser.add_argument("--split-per-abi", action="store_true", help="Package separate APKs with native libraries filtered by ABI")
    parser.add_argument("--no-pub", action="store_true")
    parser.add_argument("--log", type=Path, help="Optional complete build log")
    args = parser.parse_args()

    flutter = args.flutter or shutil.which("flutter")
    if not flutter:
        parser.error("Flutter is not on PATH; provide --flutter.")
    repository = Path(__file__).resolve().parents[1]
    app = repository / "apps" / "file_transfer"
    env = os.environ.copy()
    env["CI"] = "true"
    env["FLUTTER_SUPPRESS_ANALYTICS"] = "true"
    if args.java_home:
        java_home = args.java_home.resolve()
        suffix = ".exe" if os.name == "nt" else ""
        if not all((java_home / "bin" / f"{tool}{suffix}").is_file()
                   for tool in ("java", "javac")):
            parser.error("--java-home must contain both bin/java and bin/javac; a JRE alone cannot compile Android plugins.")
        env["JAVA_HOME"] = str(java_home)
        env["PATH"] = str(java_home / "bin") + os.pathsep + env.get("PATH", "")
    if args.android_sdk:
        env["ANDROID_HOME"] = str(args.android_sdk.resolve())
        env["ANDROID_SDK_ROOT"] = env["ANDROID_HOME"]
    if args.gradle_user_home:
        env["GRADLE_USER_HOME"] = str(args.gradle_user_home.resolve())

    java_properties: list[str] = []
    for protocol in ("http", "https"):
        value = env.get(f"{protocol.upper()}_PROXY") or env.get(f"{protocol}_proxy")
        if not value:
            continue
        proxy = urlsplit(value)
        if proxy.username or proxy.password:
            parser.error("Authenticated proxy endpoints need your approved Java credential setup; credentials will not be copied to JVM arguments.")
        if proxy.scheme != "http" or not proxy.hostname:
            parser.error("This helper translates HTTP CONNECT proxies only; configure other proxy schemes using your approved Java tooling.")
        java_properties.extend((
            f"-D{protocol}.proxyHost={proxy.hostname}",
            f"-D{protocol}.proxyPort={proxy.port or 80}",
        ))

    if java_properties:
        print("Using the currently inherited HTTP(S) proxy for this Java build.", flush=True)
        options = " ".join(java_properties)
        env["JAVA_TOOL_OPTIONS"] = f"{env.get('JAVA_TOOL_OPTIONS', '')} {options}".strip()
        # Avoid reusing a daemon with a stale per-session proxy endpoint.
        env["GRADLE_OPTS"] = f"{env.get('GRADLE_OPTS', '')} {options} -Dorg.gradle.daemon=false".strip()

    command = [flutter, "--no-version-check", "build", "apk", f"--{args.mode}"]
    if args.no_pub:
        command.append("--no-pub")
    if args.target_platform:
        command.extend(("--target-platform", args.target_platform))
    if args.split_per_abi:
        command.append("--split-per-abi")

    if args.log:
        args.log.parent.mkdir(parents=True, exist_ok=True)
        with args.log.open("w", encoding="utf-8") as output:
            result = subprocess.run(command, cwd=app, env=env, stdout=output, stderr=subprocess.STDOUT)
        print(f"Build exit code: {result.returncode}. Log: {args.log}")
    else:
        result = subprocess.run(command, cwd=app, env=env)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
