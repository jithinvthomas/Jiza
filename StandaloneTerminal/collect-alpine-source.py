"""Collect the corresponding GPL package sources for the bundled Alpine image."""
from pathlib import Path
import hashlib
import json
import re
import sys
import tarfile
import urllib.request

destination = Path(sys.argv[1]).resolve()
destination.mkdir(parents=True, exist_ok=True)
aports = destination / 'aports'
packages = ['alpine-baselayout', 'apk-tools', 'busybox', 'musl', 'pax-utils']
aports_commit = 'd01502332b773d59a09220aac959a3c18c429ce3'
archive = destination / 'aports-source.tar.gz'
if not archive.exists():
    with urllib.request.urlopen('https://codeload.github.com/alpinelinux/aports/tar.gz/' + aports_commit, timeout=120) as response:
        archive.write_bytes(response.read())
# Select only required recipes before writing: other ports contain Windows-
# reserved filenames. Materialize source bytes, never archive symlinks.
with tarfile.open(archive) as source:
    for member in source:
        path = Path(member.name.split('/', 1)[-1])
        if len(path.parts) < 3 or path.parts[0] != 'main' or path.parts[1] not in packages:
            continue
        if not (member.isfile() or member.issym() or member.islnk()):
            continue
        target = aports / path
        target.resolve().relative_to(aports.resolve())
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.extractfile(member).read())
downloads = destination / 'distfiles'
downloads.mkdir(exist_ok=True)
manifest = {'aportsCommit': aports_commit, 'archiveSHA256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'downloads': []}
for package in packages:
    directory = aports / 'main' / package
    build = (directory / 'APKBUILD').read_text(encoding='utf-8')
    for expected, name in re.findall(r'^([a-f0-9]{128})\s+([^\r\n]+)$', build, re.M):
        name = name.strip()
        assert Path(name).name == name, 'Source filename must be a basename'
        local = directory / name
        if local.exists():
            assert hashlib.sha512(local.read_bytes()).hexdigest() == expected, name
            continue
        target = downloads / name
        url = 'https://distfiles.alpinelinux.org/distfiles/v3.19/' + name
        if not target.exists():
            with urllib.request.urlopen(url, timeout=120) as response:
                target.write_bytes(response.read())
        assert hashlib.sha512(target.read_bytes()).hexdigest() == expected, name
        manifest['downloads'].append({'name': name, 'url': url, 'sha512': expected})
(destination / 'SOURCE-MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Collected verified source archives and Alpine build recipes for', ', '.join(packages))
