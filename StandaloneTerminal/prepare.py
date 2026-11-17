"""Prepare a reproducible, independent iOS Linux terminal from pinned iSH source."""
from pathlib import Path
import hashlib
import io
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request

SOURCE_COMMIT = 'ce96e698f1820b9d8db47e87c501ecb89119d7ce'
ROOT_URL = 'https://github.com/ish-app/roots/releases/download/g00712ff0a54b2839c5aa1a8ed758003ca65357dc/appstore-apk.tar.gz'
ROOT_SHA256 = '776b16416894e5a8bec220b8d4726c46bb993289e8e48fdac54a519396e40a93'

def prepare(root: Path, root_archive: Path):
    recipe = Path(__file__).resolve().parent
    actual = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    assert actual == SOURCE_COMMIT, 'Unexpected upstream source revision'
    assert hashlib.sha256(root_archive.read_bytes()).hexdigest() == ROOT_SHA256, 'Root filesystem checksum mismatch'

    config = root / 'app/iSH.xcconfig'
    config.write_text(config.read_text().replace('ROOT_BUNDLE_IDENTIFIER = app.ish.iSH', 'ROOT_BUNDLE_IDENTIFIER = com.jiza.terminal'))
    config = root / 'app/App.xcconfig'
    config.write_text(config.read_text().replace('PRODUCT_NAME = iSH', 'PRODUCT_NAME = JizaTerminal')
                      .replace('CODE_SIGN_ENTITLEMENTS = app/iSH.entitlements', 'CODE_SIGN_ENTITLEMENTS = app/JizaTerminal.entitlements'))
    (root / 'app/JizaTerminal.entitlements').write_bytes(plistlib.dumps({}))
    # Standalone storage avoids an App Group capability and does not need a paid
    # developer team. No file-provider extension is embedded in this app.
    group = root / 'app/AppGroup.m'
    old = '    NSString *appGroup = CurrentAppGroups()[0];\n    return [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:appGroup];'
    new = '    return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;'
    assert old in group.read_text()
    group.write_text(group.read_text().replace(old, new))
    pbx = root / 'iSH.xcodeproj/project.pbxproj'
    text = pbx.read_text()
    text = '\n'.join(line for line in text.split('\n') if 'iSHFileProvider.appex in Embed Foundation Extensions' not in line)
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if 'shellScript = "curl -L' in line:
            lines[index] = '\t\t\tshellScript = "bash \\\"$SRCROOT/app/jiza-rootfs.sh\\\"\\n";'
    pbx.write_text('\n'.join(lines) + '\n')
    # The remaining target is harmless when built, but its product is not shipped.
    info = root / 'app/Info.plist'
    text = info.read_text().replace('<key>CFBundleName</key>', '<key>CFBundleDisplayName</key>\n\t<string>Jiza Terminal</string>\n\t<key>CFBundleName</key>')
    text = text.replace('Programs running in iSH', 'Programs running in Jiza Terminal')
    info.write_text(text)
    scheme = root / 'iSH.xcodeproj/xcshareddata/xcschemes/iSH.xcscheme'
    scheme.write_text(scheme.read_text().replace('BuildableName = "iSH.app"', 'BuildableName = "JizaTerminal.app"'))
    about = root / 'app/AboutViewController.m'
    about.write_text(about.read_text().replace('@"iSH %@ (Build %@)"', '@"Jiza Terminal %@ (iSH-based, Build %@)"'))
    repositories = root / 'app/gen_apk_repositories.py'
    repositories.write_text(repositories.read_text().replace('http://apk.ish.app/', 'https://apk.ish.app/'))
    terminal = root / 'app/Terminal.m'
    terminal.write_text(terminal.read_text().replace('_webView = [[CustomWebView alloc] initWithFrame:webviewSize configuration:config];',
        '_webView = [[CustomWebView alloc] initWithFrame:webviewSize configuration:config];\n        _webView.accessibilityIdentifier = @"linuxTerminalWebView";'))
    controller = root / 'app/TerminalViewController.m'
    controller.write_text(controller.read_text().replace('    [super viewDidLoad];',
        '    [super viewDidLoad];\n    self.controlKey.accessibilityIdentifier = @"terminalControl";\n    self.escapeKey.accessibilityIdentifier = @"terminalEscape";\n    self.hideKeyboardButton.accessibilityIdentifier = @"terminalKeyboard";', 1))
    shutil.copy2(recipe / 'LinuxTerminalTests.m', root / 'app/UITests/UITests.m')
    # Keep original source and license acknowledgments; use Jiza's existing icon.
    icons = recipe / 'AppIcon'
    destination = root / 'app/Assets.xcassets/JizaIcon.appiconset'
    shutil.copytree(icons, destination, dirs_exist_ok=True)
    config = root / 'app/App.xcconfig'
    config.write_text(config.read_text().replace('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon', 'ASSETCATALOG_COMPILER_APPICON_NAME = JizaIcon'))

    with tarfile.open(root_archive) as source, tarfile.open(root / 'app/jiza-root.tar.gz', 'w:gz') as output:
        for member in source:
            if member.name in ('./etc/motd', './etc/hostname'):
                continue
            output.addfile(member, source.extractfile(member) if member.isfile() else None)
        for name, data in {
            './etc/motd': b'Jiza Terminal - local Alpine Linux on iPhone\nPowered by the open-source iSH emulator. No remote server required.\nInstall tools: apk update && apk add bash git python3 nano\n\n',
            './etc/hostname': b'jiza\n',
        }.items():
            member = tarfile.TarInfo(name); member.mode = 0o644; member.size = len(data)
            output.addfile(member, io.BytesIO(data))
    (root / 'app/jiza-rootfs.sh').write_text('''#!/bin/bash
set -euo pipefail
cp "$SRCROOT/app/jiza-root.tar.gz" "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/root.tar.gz"
mkdir -p "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Licenses"
cp "$SRCROOT/LICENSE.md" "$SRCROOT/LICENSE.IOS" "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Licenses/"
''')
    provenance = {'name': 'Jiza Terminal', 'upstream': 'https://github.com/ish-app/ish', 'sourceCommit': SOURCE_COMMIT,
                  'rootFilesystem': {'url': ROOT_URL, 'sha256': ROOT_SHA256, 'distribution': 'Alpine Linux 3.19 x86'},
                  'bundleIdentifier': 'com.jiza.terminal', 'storage': 'private on-device Documents directory',
                  'remoteServerRequired': False, 'license': 'GPLv3 with upstream iOS additional terms'}
    (root / 'JIZA-PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print(json.dumps(provenance))

if __name__ == '__main__':
    prepare(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
