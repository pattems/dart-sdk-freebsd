#!/bin/sh
# Regenerate lang/dart's files/patch-* (make makepatch form) from the git
# series. Run on FreeBSD.
#
#   to-makepatch.sh <portdir> <seriesdir> <outdir>
#
# <seriesdir> holds the git-format patches (patches/<version>/ in this
# repository, including the Perfetto and zlib patches). Set PORTSDIR and
# DISTDIR if the defaults below don't match your system. The patches are
# applied with -p1 to a copy of <portdir>, every
# touched file gets a pristine .orig from the distfile (an empty one for new
# files) so files patched by several commits are diffed against the
# original, and `make makepatch` writes the port's patches to <outdir>/files.
# Finally the new patches are applied to a fresh extract and the trees are
# compared.
set -eu

PORT=$(realpath "$1")
SERIES=$(realpath "$2")
OUT=$3
: "${PORTSDIR:=/poudriere/ports/q4}"
: "${DISTDIR:=/poudriere/distfiles}"
export PORTSDIR DISTDIR
W=/tmp/to-makepatch
rm -rf "$W" "$OUT"
mkdir -p "$W/a/lang" "$W/b/lang" "$OUT"

# 1. Apply the git series.
cp -R "$PORT" "$W/a/lang/dart"
rm -f "$W/a/lang/dart/files"/patch-*
cp "$SERIES"/patch-* "$W/a/lang/dart/files/"
make -C "$W/a/lang/dart" WRKDIRPREFIX="$W/wa" PATCH_STRIP=-p1 BATCH=yes patch \
    >/dev/null
WA=$(make -C "$W/a/lang/dart" WRKDIRPREFIX="$W/wa" -V WRKSRC)
TOP=$(basename "$WA")
echo "series: $(ls "$SERIES" | grep -c '^patch-') patches applied"

# 2. Pristine .orig for every touched file.
grep -h '^+++ b/' "$SERIES"/patch-* | sed 's|^+++ b/||' | sort -u > "$W/touched"
grep -B1 -h '^+++ b/' "$SERIES"/patch-* | grep -A1 '^--- /dev/null' |
    sed -n 's|^+++ b/||p' | sort -u > "$W/new"
find "$WA" -name '*.orig' -delete
SRCDIST=$DISTDIR/dart/$(make -C "$W/a/lang/dart" -V DISTFILES | tr ' ' '\n' |
    grep -- '-src\.tar\.xz$')
comm -23 "$W/touched" "$W/new" | sed "s|^|$TOP/|" > "$W/members"
mkdir "$W/pristine"
tar -xf "$SRCDIST" -C "$W/pristine" -T "$W/members"
# Test files (tests/, runtime/tests/, *_test.cc/.dart) are for upstream only:
# the port doesn't build or run the tests, so put them back to pristine and
# leave them out of the port's patches.
TESTRE='(^|/)tests/|_test\.(cc|dart)$'
while read -r f; do
	if echo "$f" | grep -qE "$TESTRE"; then
		cp -p "$W/pristine/$TOP/$f" "$WA/$f"
		echo "  skipped (test file): $f"
		continue
	fi
	if grep -qxF "$f" "$W/new"; then
		# Release timestamp (all distfile members share it), so the
		# patch header doesn't change on every run.
		: > "$WA/$f.orig"
		touch -r "$W/pristine/$(head -1 "$W/members")" "$WA/$f.orig"
	else
		cp -p "$W/pristine/$TOP/$f" "$WA/$f.orig"
	fi
done < "$W/touched"
echo "touched: $(wc -l < "$W/touched") files ($(wc -l < "$W/new") new," \
    "$(grep -cE "$TESTRE" "$W/touched") test files skipped)"

# 3. makepatch.
rm -f "$W/a/lang/dart/files"/patch-*
make -C "$W/a/lang/dart" WRKDIRPREFIX="$W/wa" makepatch >/dev/null
cp -R "$W/a/lang/dart/files" "$OUT/files"
echo "makepatch: $(ls "$OUT/files" | grep -c '^patch-') patch files"

# 4. Apply the new patches the way the port does and compare the trees.
cp -R "$W/a/lang/dart" "$W/b/lang/dart"
make -C "$W/b/lang/dart" WRKDIRPREFIX="$W/wb" BATCH=yes patch >/dev/null
WB=$(make -C "$W/b/lang/dart" WRKDIRPREFIX="$W/wb" -V WRKSRC)
find "$WA" "$WB" -name '*.orig' -delete
if diff -r -q "$WA" "$WB"; then
	echo "OK: the port's patches give the same tree as the git series"
else
	echo "MISMATCH" >&2
	exit 1
fi
rm -rf "$W"
