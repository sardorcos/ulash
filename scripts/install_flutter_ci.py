#!/usr/bin/env python3
"""Install the verified Linux SDK used by the CI workflow, without modifying it."""
import argparse
import hashlib
import os
from pathlib import Path
import tarfile
import tempfile
import urllib.request

VERSION = '3.50.1'
SHA256 = '4ad17fc8462fbcef2ba19ff4a78c0a16b7147fde1add8578e267ea62cdb92678'
URL = f'https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_{VERSION}-stable.tar.xz'

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--destination', required=True, type=Path)
args = parser.parse_args()
args.destination.mkdir(parents=True, exist_ok=True)
if (args.destination / 'flutter').exists():
    raise SystemExit('Destination already contains an SDK; use a fresh directory.')
with tempfile.TemporaryDirectory(prefix='transfer-flutter-sdk-') as temp:
    archive = Path(temp) / 'flutter.tar.xz'
    urllib.request.urlretrieve(URL, archive)
    with archive.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != SHA256:
            raise SystemExit('Flutter SDK checksum mismatch')
    with tarfile.open(archive) as stream:
        stream.extractall(args.destination, filter='data')
flutter_bin = args.destination.resolve() / 'flutter' / 'bin'
if os.environ.get('GITHUB_PATH'):
    with open(os.environ['GITHUB_PATH'], 'a', encoding='utf-8') as stream:
        stream.write(str(flutter_bin) + '\n')
print(f'Installed Flutter {VERSION}: {flutter_bin}')
