# Jiza Terminal — standalone Linux for iOS

This builds an independent, free iPhone/iPad terminal with an on-device Alpine
Linux filesystem and an interactive shell. It uses the open-source iSH x86
emulator and Linux syscall translation, rather than an SSH connection or a list
of simulated commands. There is no server, subscription, remote gateway or
jailbreak requirement. Network access is needed to install packages, not to run
already installed local commands.

The app has its own identity, `com.jiza.terminal`. It stores its filesystem in
its private Documents directory and does not embed the upstream file-provider
extension or require an App Group. This keeps the terminal independent of the
all-in-one Jiza app and avoids an App Group signing prerequisite. An iOS signing
identity is still needed to install a custom IPA; the app code is free.

Source: https://github.com/ish-app/ish at
`ce96e698f1820b9d8db47e87c501ecb89119d7ce`, under GPLv3 and the upstream iOS
additional terms. All original copyright notices and source attribution remain.
The build artifact includes the modified source, pinned submodule sources,
root filesystem, and this build recipe. The binary filesystem is upstream's
Alpine 3.19 x86 image; package sources and build recipes are maintained by Alpine
and iSH. Root image SHA-256:
`776b16416894e5a8bec220b8d4726c46bb993289e8e48fdac54a519396e40a93`.

After installing, use:

```sh
apk update
apk add bash git python3 nano
python3 --version
```

The keyboard includes Ctrl, Escape, Tab and arrow controls. Linux processes,
pipes, redirects, scripts, package installs and persistent files run locally.
The emulated x86 architecture and supported Linux syscalls limit compatibility
and performance. This does not promise every Android Termux package, Docker,
native Android binaries or local Claude/Codex CLI support. iOS may suspend the
app in the background.

The workflow tests shell output and persistence across an app restart, installs
Python/Bash/Git/Nano through apk and runs Python/Bash, and interrupts a Linux
process with Ctrl+C. It then archives an unsigned arm64 device app. Physical
iPhone checks remain necessary after signing.

To reproduce on a Mac, clone the pinned upstream revision, initialize
`deps/libapps` and `deps/libarchive`, download the pinned root archive, then run
`python3 prepare.py /path/to/ish /path/to/appstore-apk.tar.gz`. Install the tools
listed in the workflow and open `iSH.xcodeproj`, selecting the iSH scheme.
