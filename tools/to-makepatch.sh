#!/bin/sh
# Regenerate lang/dart's files/patch-* (make makepatch form) from the git
# series. Run on FreeBSD.
#
#   to-makepatch.sh <portdir> <seriesdir> <outdir>
#
# <seriesdir> holds the git-format patches (patches/<version>/ in this
# repository, including the Perfetto and zlib patches). Set PORTSDIR and
# DISTDIR if the defaults below don't match your system. The patches are
# applied with -p1 to an extract of <portdir>, every touched file gets a
# pristine .orig from the distfile so files patched by several commits are
# diffed against the original, and `make makepatch` writes the port's patches
# to <outdir>/files. makepatch keeps the comment header of each existing
# patch in <portdir>/files, so add one by hand for a newly patched file.
# Files the series adds are not patches: they are copied to
# <outdir>/files/<basename>, and the port's post-patch target must install
# them. Finally the new patches are applied to a fresh extract the way the
# port does and the trees are compared.
set -eu

PORT=$(realpath "$1")
SERIES=$(realpath "$2")
OUT=$3
: "${PORTSDIR:=/poudriere/ports/q4}"
: "${DISTDIR:=/poudriere/distfiles}"
export PORTSDIR DISTDIR
W=/tmp/to-makepatch
rm -rf "$W" "$OUT"
mkdir -p "$W/a/lang" "$W/b/lang" "$W/newfiles" "$OUT"

# 1. Apply the git series. Extract only and apply the series by hand: the
# port's own patches and post-patch must not run here.
cp -R "$PORT" "$W/a/lang/dart"
make -C "$W/a/lang/dart" WRKDIRPREFIX="$W/wa" BATCH=yes extract >/dev/null
WA=$(make -C "$W/a/lang/dart" WRKDIRPREFIX="$W/wa" -V WRKSRC)
TOP=$(basename "$WA")
for p in "$SERIES"/patch-*; do
	patch -f -s -p1 -d "$WA" < "$p"
done
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
: > "$W/patched"
while read -r f; do
	if echo "$f" | grep -qE "$TESTRE"; then
		if grep -qxF "$f" "$W/new"; then
			rm "$WA/$f"
		else
			cp -p "$W/pristine/$TOP/$f" "$WA/$f"
		fi
		echo "  skipped (test file): $f"
		continue
	fi
	if grep -qxF "$f" "$W/new"; then
		n=$(basename "$f")
		if [ -e "$W/newfiles/$n" ]; then
			echo "two new files are named $n" >&2
			exit 1
		fi
		cp -p "$WA/$f" "$W/newfiles/$n"
		echo "  new file: $f -> files/$n"
	else
		cp -p "$W/pristine/$TOP/$f" "$WA/$f.orig"
		echo "$f" >> "$W/patched"
	fi
done < "$W/touched"
echo "touched: $(wc -l < "$W/touched") files ($(wc -l < "$W/new") new," \
    "$(grep -cE "$TESTRE" "$W/touched") test files skipped)"

# 3. makepatch. The existing patches stay so that makepatch keeps their
# comments; drop those for files the series no longer patches.
for p in "$W/a/lang/dart/files"/patch-*; do
	[ -e "$p" ] || continue
	t=$(sed -n 's|^+++ \([^[:blank:]]*\).*|\1|p' "$p")
	if ! grep -qxF "$t" "$W/patched"; then
		echo "  dropped: $(basename "$p") ($t)"
		rm "$p"
	fi
done
make -C "$W/a/lang/dart" WRKDIRPREFIX="$W/wa" makepatch >/dev/null
for p in "$W/a/lang/dart/files"/patch-*; do
	if head -1 "$p" | grep -q '^--- '; then
		echo "  no header yet: $(basename "$p")"
	fi
done
for n in "$W/newfiles"/*; do
	[ -e "$n" ] && cp -p "$n" "$W/a/lang/dart/files/"
done
cp -R "$W/a/lang/dart/files" "$OUT/files"
echo "makepatch: $(ls "$OUT/files" | grep -c '^patch-') patch files," \
    "$(ls "$W/newfiles" | wc -l | tr -d ' ') new files"

# 4. Apply the new patches the way the port does (including post-patch, which
# installs the new files) and compare the trees.
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
