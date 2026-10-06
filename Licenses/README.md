# VideoLAN libraries
Jiza uses unmodified MobileVLCKit 3.7.3 from the official CocoaPods spec, with the LGPL-2.1-or-later license in VLCKit-LGPL-2.1.txt.

Source and library build instructions: https://code.videolan.org/videolan/VLCKit
Distribution: https://download.videolan.org/pub/cocoapods/prod/
Pinned package specification: https://github.com/CocoaPods/Specs/blob/master/Specs/b/f/7/MobileVLCKit/3.7.3/MobileVLCKit.podspec.json

To rebuild Jiza with a modified compatible VLCKit, follow VideoLAN's iOS build instructions, substitute the resulting MobileVLCKit framework for the Pod-provided framework, run xcodegen, integrate the framework, and build the InteraMusicPlayer scheme. The repository contains Jiza's source and project generator configuration. Preserve this notice and the library license in redistributed builds.
