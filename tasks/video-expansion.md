# Jiza Video expansion

The home menu separates Music and Video. Video gets its own cobalt-glass film/play logo, Files/folder library with search and sorting, queue navigation, resume positions, native playback with VLC fallback, embedded and external subtitles, audio tracks, speed, fit/fill/stretch, seek gestures, lock, repeat, sleep timer and direct network URLs. Native playback retains AirPlay/Picture in Picture; VLC fallback does not promise those features.

Keep music ownership/remote commands intact. Native MP4 tests remain and broad-codec fixtures exercise VLC. File access must survive playback. Closing/replacing media cancels pending work. Protected media, arbitrary site downloads, private browser tabs, SMB/DLNA discovery, casting from VLC, equalizers and desktop-only player features are outside this increment and must not be advertised as implemented.

Verification: both Mac simulator workflows, regression tests, local MKV fixture, and unsigned IPA. Hardware Bluetooth, PiP, AirPlay and external file providers require device checks.
