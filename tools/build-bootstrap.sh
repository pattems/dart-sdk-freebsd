#!/bin/sh
# Build a Dart SDK on FreeBSD with another FreeBSD Dart SDK as the host: one
# step of the bootstrap chain described in docs/bootstrap.md.
#
#   build-bootstrap.sh <src.tar.xz> <patch> <host-sdk.tar.xz> <out.tar.xz>
#
# <src.tar.xz> is a source distfile made by make-dist.sh,
# <patch> the FreeBSD changes for that version as one -p1 patch, and
# <host-sdk.tar.xz> an SDK tarball with top directory dart-sdk/, such as the
# port's bootstrap distfile. Writes the new SDK (without *.sym files) to
# <out.tar.xz>. Refuses to run with the Linux compatibility layer loaded, so
# the result can't depend on Linux binaries. Needs gn, ninja, python3.
set -eu

[ $# -eq 4 ] ||
	{ echo "usage: build-bootstrap.sh <src.tar.xz> <patch> <host-sdk.tar.xz> <out.tar.xz>"; exit 2; }
SRC=$(realpath "$1")
PATCH=$(realpath "$2")
HOST=$(realpath "$3")
# The output doesn't exist yet, so resolve its directory instead.
OUT=$(cd "$(dirname "$4")" && pwd)/$(basename "$4")

if kldstat -q -m linux64elf 2>/dev/null || kldstat -q -n linux64.ko; then
	echo "The Linux compatibility layer (linux64) is loaded; unload it first." >&2
	exit 1
fi

W=$(mktemp -d -t dart-bootstrap)
trap 'rm -rf "$W"' EXIT
tar -xJf "$SRC" -C "$W"
cd "$W"/dart-sdk-*
patch -s -p1 < "$PATCH"
mkdir -p tools/sdks
tar -xJf "$HOST" -C tools/sdks
echo "host:  $(tools/sdks/dart-sdk/bin/dart --version 2>&1)"

# The port's GN arguments, without Perfetto.
mkdir -p out/release
cat > out/release/args.gn <<'EOF'
target_os = "freebsd"
host_cpu = "x64"
target_cpu = "x64"
dart_target_arch = "x64"
dart_use_compressed_pointers = false
dart_use_crashpad = false
dart_snapshot_kind = "app-jit"
is_debug = false
is_release = true
is_product = false
dart_debug = false
dart_runtime_mode = "develop"
is_clang = true
use_rbe = false
verify_sdk_hash = false
dart_version_git_info = false
EOF
gn gen out/release
ninja -C out/release create_sdk

D=$PWD/out/release/dart-sdk/bin/dart
echo "built: $($D --version 2>&1)"
mkdir "$W/hello"
echo 'void main() => print("hello");' > "$W/hello/hello.dart"
$D compile exe "$W/hello/hello.dart" -o "$W/hello/hello" >/dev/null
"$W/hello/hello"

cd out/release
find dart-sdk -name '*.sym' -delete
tar -cf - dart-sdk | xz -T0 -6 > "$OUT"
ls -l "$OUT"
