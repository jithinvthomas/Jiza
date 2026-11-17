# Jiza terminal and desktop input

Desktop sessions now have a Keyboard button and a Pointer menu. Keyboard toggles
Guacamole's own on-screen keyboard, including modifiers and navigation keys.
Pointer offers a relative touchpad cursor or direct touch. The script uses the
existing Guacamole 1.6 menu controls, checks the client route and is only invoked
on the configured gateway origin. A different gateway shows recovery instructions.
It does not inject user text or synthesize remote key events.

Terminal has three destinations: this iPhone, Oracle and Windows. The local shell
runs bundled Unix commands through ios_system inside Jiza's iOS sandbox. Files
start in Documents/Terminal, visible in Files under Jiza. Pipes, redirection and
working-directory changes are real; history and the transcript remain in memory.
Commands use EOF input and display their result on completion. Interactive editors,
a Linux package manager, Python/Node, and locally running Claude/Codex are not part
of this initial local shell. Use Oracle or Windows for full interactive programs.
Guacamole terminal connection URLs with an encoded #/client/ fragment are accepted;
arbitrary fragments, embedded credentials, non-HTTPS URLs and query tokens are rejected.

NativeShell/build.sh builds the ios_system core from pinned v3.0.6 source with
NSLog disabled because the upstream core otherwise logs full command lines.
The remaining files/shell/text/awk/tar frameworks are pinned to published v3.0.6
URLs and SHA-256 checksums in Packages/JizaShell/Package.swift. No downloaded code
is executed on the iPhone; the bundled framework code is signed with the app.
Build NativeShell for the chosen SDK before running XcodeGen, alongside TorrentNative.
Copyright and license notices ship in Licenses.

## Investigation and validation

REA (morluto/rea) 6.7.0 was installed locally and used to analyze Guacamole 1.6's
input controller. The full deployed 730 KB bundle exceeded its five-minute parser
budget; a focused controller analysis succeeded with a bounded semantic graph.
Static evidence does not establish runtime behavior. Separate live tests on the
personal private gateway passed keyboard show/hide, touchpad and direct-touch
selection for both Oracle and Windows desktop, without sending remote keystrokes
or recording desktop contents. The private addresses and login are not bundled.

New XCTest coverage executes native pipelines, verifies real file contents and
working-directory persistence, tests command errors and safe Guacamole terminal
URLs, and exercises input control selection in WKWebView. A UI test runs a local
echo command and requires its output separately from the entered command line.
The full iOS compatibility/native suites and unsigned device archive must pass
before publishing an updated IPA. Physical iPhone keyboard and gestures still
need device verification.
