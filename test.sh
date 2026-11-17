#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build/module-cache .build/cache .build/config .build/security
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"
swift run --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache" GridCoreChecks
