#!/bin/sh
# The Linux version of tools/make-dist.sh, kept for the record: it made the
# 3.13.5 source distfile, before the FreeBSD one existed. It builds the same
# distfile (a gclient checkout of the Dart SDK at a release tag, without the
# prebuilt toolchains) using upstream's gclient and cipd as they are. Run on
# Linux (WSL is fine); needs git, python3, xz, GNU tar.
#
#   make-dist.sh 3.13.5 [workdir]
#
# Produces <workdir>/dart-sdk-<version>-src.tar.xz with top directory
# dart-sdk-<version>/.
set -eu

VERSION=${1:?usage: make-dist.sh <version> [workdir]}
WORK=${2:-$HOME/dart-dist}
NAME=dart-sdk-${VERSION}

mkdir -p "$WORK"
cd "$WORK"

if [ ! -d depot_tools ]; then
	git clone -q --depth 1 \
	    https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH="$WORK/depot_tools:$PATH" DEPOT_TOOLS_UPDATE=0 \
    DEPOT_TOOLS_METRICS=0
# Keep the output independent of who runs this: package_config.json records
# the pub cache path, and Python would leave __pycache__ behind.
export PUB_CACHE=/nonexistent/pub-cache PYTHONDONTWRITEBYTECODE=1

rm -rf "checkout-$VERSION"
mkdir "checkout-$VERSION"
cd "checkout-$VERSION"
cat > .gclient <<EOF
solutions = [{
  "name": "sdk",
  "url": "https://dart.googlesource.com/sdk.git@refs/tags/${VERSION}",
  "deps_file": "DEPS",
  "managed": False,
  "custom_deps": {},
  "custom_vars": {"download_reclient": False},
}]
EOF
# The hooks generate .dart_tool/package_config.json and other files the build
# needs, so keep them.
gclient sync --no-history --shallow -D -j 16

# Timestamp of the release commit, used for every file in the archive.
MTIME=$(git -C sdk log -1 --format=%ct)

# Prebuilt Linux binaries and tools the FreeBSD build does not use. The port
# supplies clang, gn, ninja and a bootstrap Dart SDK itself.
cat > ../exclude-$VERSION <<'EOF'
.git
.cipd
sdk/buildtools/.versions
sdk/buildtools/linux-x64
sdk/buildtools/linux-arm64
sdk/buildtools/linux64
sdk/buildtools/mac-x64
sdk/buildtools/mac-arm64
sdk/buildtools/reclient-linux
sdk/buildtools/sysroot
sdk/buildtools/gn
sdk/buildtools/ninja
sdk/buildtools/clang_format
sdk/tools/sdks/dart-sdk
sdk/third_party/d8
sdk/third_party/gsutil
sdk/third_party/firefox_jsshell
sdk/third_party/jsc
sdk/third_party/browsers
EOF

# Rename the checkout's sdk/ to the versioned top directory in the archive.
tar --exclude-vcs -X ../exclude-$VERSION \
    --transform "s,^sdk,${NAME}," \
    --sort=name --mtime="@$MTIME" --owner=0 --group=0 --numeric-owner \
    --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
    -cf - sdk | xz -T8 -6 > "../${NAME}-src.tar.xz"

cd ..
ls -l "${NAME}-src.tar.xz"
sha256sum "${NAME}-src.tar.xz"
