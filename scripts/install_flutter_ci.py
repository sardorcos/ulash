#!/usr/bin/env python3
"""Install the pinned official Flutter SDK for the current CI host.

Archive hashes come from Google's Flutter 3.50.1 release manifests. Updating
Flutter requires reviewing this table together with the project's lockfiles.
The installer does not modify the SDK or download an unpinned "latest" version.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile

VERSION = '3.50.1'
RELEASES = {
    ('Linux', 'x64'): (
        f'stable/linux/flutter_linux_{VERSION}-stable.tar.xz',
        '4ad17fc8462fbcef2ba19ff4a78c0a16b7147fde1add8578e267ea62cdb92678',
    ),
    ('Darwin', 'x64'): (
        f'stable/macos/flutter_macos_{VERSION}-stable.zip',
        '5c3d3bbabc8edd58eb98605047c59c31a82895cfe7d119318d0f62cdbd5d47ed',
    ),
    ('Darwin', 'arm64'): (
        f'stable/macos/flutter_macos_arm64_{VERSION}-stable.zip',
        '872883d49965e0cc1d8e477d2d87f2f45930d13f94b34889e53783586f04c715',
    ),
    ('Windows', 'x64'): (
        f'stable/windows/flutter_windows_{VERSION}-stable.zip',
        '33c1e3d4dd08f1136ddb9c7976cfd2b0ab20296f1565b78ba176a4cbb4e140eb',
    ),
}


def release_for(system: str, machine: str) -> tuple[str, str]:
    arch = {'amd64': 'x64', 'x86_64': 'x64', 'arm64': 'arm64',
            'aarch64': 'arm64'}.get(machine.lower(), machine.lower())
    if (system, arch) not in RELEASES:
        raise SystemExit(f'No verified SDK is configured for {system}/{arch}.')
    archive, digest = RELEASES[(system, arch)]
    return ('https://storage.googleapis.com/flutter_infra_release/releases/'
            + archive, digest)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', required=True, type=Path)
    parser.add_argument('--print-plan', action='store_true',
                        help='Print the selected pinned release without downloading it')
    args = parser.parse_args()
    url, expected_hash = release_for(platform.system(), platform.machine())
    if args.print_plan:
        print(json.dumps({'version': VERSION, 'url': url,
                          'sha256': expected_hash}, indent=2))
        return
    args.destination.mkdir(parents=True, exist_ok=True)
    if (args.destination / 'flutter').exists():
        raise SystemExit('Destination already contains an SDK; use a fresh directory.')
    with tempfile.TemporaryDirectory(prefix='transfer-flutter-sdk-') as temp:
        archive = Path(temp) / ('flutter.tar.xz' if url.endswith('.tar.xz')
                                else 'flutter.zip')
        urllib.request.urlretrieve(url, archive)
        with archive.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != expected_hash:
                raise SystemExit('Flutter SDK checksum mismatch')
        if archive.name.endswith('.tar.xz'):
            with tarfile.open(archive) as stream:
                stream.extractall(args.destination, filter='data')
        else:
            # Validate every entry before invoking macOS unzip, which preserves
            # the executable bits and framework symlinks in the official SDK.
            destination = args.destination.resolve()
            with zipfile.ZipFile(archive) as stream:
                for entry in stream.infolist():
                    target = (destination / entry.filename).resolve()
                    if not target.is_relative_to(destination):
                        raise SystemExit('Unsafe SDK archive path')
                if platform.system() == 'Darwin':
                    subprocess.run(['unzip', '-q', str(archive), '-d',
                                    str(destination)], check=True)
                else:
                    stream.extractall(destination)
    flutter_bin = args.destination.resolve() / 'flutter' / 'bin'
    if os.environ.get('GITHUB_PATH'):
        with open(os.environ['GITHUB_PATH'], 'a', encoding='utf-8') as stream:
            stream.write(str(flutter_bin) + '\n')
    print(f'Installed Flutter {VERSION}: {flutter_bin}')


if __name__ == '__main__':
    main()
