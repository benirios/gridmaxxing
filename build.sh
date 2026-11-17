#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build/module-cache .build/cache .build/config .build/security
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"
swift build -c release --product MissionGrid --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
mkdir -p 'dist/Mission Grid.app/Contents/MacOS' 'dist/Mission Grid.app/Contents/Resources'
cp .build/release/MissionGrid 'dist/Mission Grid.app/Contents/MacOS/MissionGrid'
cp Resources/Info.plist 'dist/Mission Grid.app/Contents/Info.plist'
cp THIRD_PARTY.md 'dist/Mission Grid.app/Contents/Resources/THIRD_PARTY.md'
codesign --force --sign - --identifier local.MissionGrid 'dist/Mission Grid.app'
print 'Built dist/Mission Grid.app'
