#!/bin/sh
# Build the lang/dart source distfile on FreeBSD: a gclient checkout of the
# Dart SDK at a release tag, without the prebuilt Linux and macOS toolchains,
# as a tar.xz whose contents don't depend on the machine or the user running
# it. gclient fetches the git dependencies. There is no FreeBSD cipd client,
# so gclient gets a no-op stand-in, and the CIPD packages the distfile keeps
# (data such as DevTools, not the prebuilt toolchains) are downloaded over
# CIPD's HTTP API instead. Needs git, python3, gtar, xz, unzip, fetch.
#
# Two DEPS hooks run Dart from tools/sdks/dart-sdk, where gclient puts the
# SDK pinned in DEPS (sdk_tag). Pass a FreeBSD build of that SDK, i.e. the
# bootstrap this release builds with; it is not included in the distfile.
#
#   make-dist.sh <version> <host-sdk.tar.xz> [workdir]
#
# Produces <workdir>/dart-sdk-<version>-src.tar.xz with top directory
# dart-sdk-<version>/.
set -eu

USAGE="usage: make-dist.sh <version> <host-sdk.tar.xz> [workdir]"
VERSION=${1:?$USAGE}
HOST_SDK=$(realpath "${2:?$USAGE}")
WORK=${3:-$HOME/dart-dist}
NAME=dart-sdk-${VERSION}
CIPD=https://chrome-infra-packages.appspot.com

mkdir -p "$WORK"
cd "$WORK"
if [ ! -d depot_tools ]; then
	git clone -q --depth 1 \
	    https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export DEPOT_TOOLS_UPDATE=0 DEPOT_TOOLS_METRICS=0
# Keep the output independent of who runs this: package_config.json records
# the pub cache path, and Python would leave __pycache__ behind.
export PUB_CACHE=/nonexistent/pub-cache PYTHONDONTWRITEBYTECODE=1

rm -rf "checkout-$VERSION"
mkdir "checkout-$VERSION"
cd "checkout-$VERSION"
git clone -q --depth 1 --branch "$VERSION" \
    https://dart.googlesource.com/sdk.git sdk

# The .gclient file, and the CIPD packages the distfile keeps: everything but
# the prebuilt toolchains, and only those whose DEPS condition holds for a
# default Linux checkout (what make-dist.sh's gclient run downloads).
python3 - "$WORK/checkout-$VERSION" "$VERSION" <<'EOF'
import json, sys
root, version = sys.argv[1], sys.argv[2]
ns = {'Var': lambda n: '{' + n + '}', 'Str': str}
exec(open(root + '/sdk/DEPS').read(), ns)
class Vars(dict):
    # Conditions sometimes compare with bare names (host_os == win), which
    # gclient treats as strings.
    def __missing__(self, key):
        return key
vars_ = Vars(ns['vars'], download_reclient=False, host_os='linux',
             host_cpu='x64', checkout_win=False)
excluded = ['sdk/buildtools', 'sdk/tools/sdks/dart-sdk', 'sdk/third_party/d8',
            'sdk/third_party/gsutil', 'sdk/third_party/firefox_jsshell',
            'sdk/third_party/jsc', 'sdk/third_party/browsers']
fetch = []
for path, d in ns['deps'].items():
    if not (isinstance(d, dict) and d.get('dep_type') == 'cipd'):
        continue
    path = path.replace('{dart_root}', 'sdk')
    cond = d.get('condition')
    if cond and not eval(cond, {}, vars_):
        continue
    if any(path == e or path.startswith(e + '/') for e in excluded):
        continue
    for p in d['packages']:
        fetch.append((path, p['package'], p['version'].format(**vars_)))
open(root + '/.gclient', 'w').write(
    'solutions = [%r]\n' % {
        'name': 'sdk',
        'url': 'https://dart.googlesource.com/sdk.git@refs/tags/' + version,
        'deps_file': 'DEPS', 'managed': False, 'custom_deps': {},
        'custom_vars': {'download_reclient': False}})
with open(root + '/cipd-fetch.txt', 'w') as f:
    for path, pkg, ver in fetch:
        f.write(f'{path} {pkg} {ver}\n')
print(f'{len(fetch)} CIPD packages to download')
EOF

# gclient runs `cipd ensure` for the CIPD dependencies after the git ones.
mkdir -p "$WORK/nocipd"
printf '#!/bin/sh\nexit 0\n' > "$WORK/nocipd/cipd"
chmod +x "$WORK/nocipd/cipd"
PATH="$WORK/nocipd:$PATH" \
    python3 "$WORK/depot_tools/gclient.py" sync --no-history --nohooks -j 16

while read -r path pkg ver; do
	echo "cipd: $pkg ($ver) -> $path"
	# Unpack on top of the directory, like cipd: some of these directories
	# also hold files from the sdk repository.
	mkdir -p "$path"
	fetch -q -o /tmp/cipd.zip "$CIPD/dl/$pkg/+/$ver"
	unzip -q -o /tmp/cipd.zip -d "$path"
	rm -rf "$path/.cipdpkg" /tmp/cipd.zip
	# unzip keeps only the owner's permission bits; cipd makes the files
	# readable (and executable, where they are) by everyone.
	chmod -R go=u,go-w "$path"
done < cipd-fetch.txt

# The DEPS hooks that generate files the build needs. (buildtools/update.py
# only fetches toolchains the distfile excludes.)
rm -rf sdk/tools/sdks/dart-sdk && mkdir -p sdk/tools/sdks
tar -xJf "$HOST_SDK" -C sdk/tools/sdks
echo "hooks run with: $(sdk/tools/sdks/dart-sdk/bin/dart --version 2>&1)"
python3 sdk/tools/generate_package_config.py
python3 sdk/tools/generate_sdk_version_file.py
python3 sdk/tools/generate_large_tests.py

MTIME=$(git -C sdk log -1 --format=%ct)
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
gtar --exclude-vcs -X ../exclude-$VERSION \
    --transform "s,^sdk,${NAME}," \
    --sort=name --mtime="@$MTIME" --owner=0 --group=0 --numeric-owner \
    --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
    -cf - sdk | xz -T0 -6 > "../${NAME}-src.tar.xz"
cd ..
ls -l "${NAME}-src.tar.xz"
sha256 "${NAME}-src.tar.xz"
