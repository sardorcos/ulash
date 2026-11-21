#!/usr/bin/env python3
"""Run the project's real analysis and test suites without native device claims."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', help='Path to Flutter executable (or flutter.bat)')
    args = parser.parse_args()
    flutter = args.flutter or shutil.which('flutter')
    if not flutter:
        parser.error('Flutter SDK was not found. Supply --flutter /path/to/flutter/bin/flutter.')
    flutter = str(Path(flutter).resolve())
    dart = str(Path(flutter).parent / ('dart.bat' if os.name == 'nt' else 'dart'))
    root = Path(__file__).resolve().parent.parent
    env = os.environ.copy()
    env.update(CI='true', FLUTTER_SUPPRESS_ANALYTICS='true')
    jobs = [
        ('packages/transfer_core', [dart, 'pub', 'get', '--enforce-lockfile']),
        ('packages/transfer_core', [dart, 'analyze', '--fatal-infos']),
        ('packages/transfer_core', [dart, 'test', '--reporter', 'expanded']),
        ('apps/file_transfer', [flutter, '--no-version-check', 'pub', 'get', '--enforce-lockfile']),
        ('apps/file_transfer', [flutter, '--no-version-check', 'analyze', '--no-pub']),
        ('apps/file_transfer', [flutter, '--no-version-check', 'test', '--reporter', 'expanded']),
    ]
    for directory, command in jobs:
        print(f'\n[{directory}] {Path(command[0]).name} {" ".join(command[1:])}', flush=True)
        result = subprocess.run(command, cwd=root / directory, env=env)
        if result.returncode:
            return result.returncode
    print('\nValidation passed. Native device acceptance remains a separate gate.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
