# The initial bootstrap

Building Dart needs a Dart SDK to run the Dart parts of the build ([`docs/bootstrap.md`](../docs/bootstrap.md) explains why). Every FreeBSD bootstrap after the first is built on FreeBSD by the previous one. The first one, for Dart 3.13.5, had to start from upstream's Linux SDK. This folder records how that was done; none of it is needed for later releases.

## The 3.13.5 bootstrap

It was made in two stages, in October 2026:

1. **Stage 0:** Dart 3.13.5 with this port's patches, built on FreeBSD 15.1 amd64 with the Linux compatibility layer loaded. The compilers and linker were FreeBSD's; only the build's Dart steps (front end, snapshot generators and so on) ran on upstream's Linux SDK. The result is a native FreeBSD SDK.
2. **Stage 1:** the same source built again with the stage 0 SDK as the host, and the Linux compatibility layer unloaded. This shows that the FreeBSD SDK can rebuild itself without any Linux binaries.

The published `dart-sdk-3.13.5-bootstrap-freebsd15-amd64.tar.xz` is the stage 1 SDK, with the debug symbol files (`*.sym`) removed and the binaries and AOT snapshots stripped.

This only has to happen once per architecture. Everything since then, including bootstraps for new releases, is built on FreeBSD from this one.

## The 3.13.5 source distfile

[`make-dist.sh`](make-dist.sh) here is the Linux version of [`tools/make-dist.sh`](../tools/make-dist.sh). It made `dart-sdk-3.13.5-src.tar.xz`, before the FreeBSD script existed. It runs upstream's `gclient` and `cipd` unchanged, which only run on Linux, macOS and Windows.

The FreeBSD script replaced it after [`tarcmp.py`](tarcmp.py) showed the two give the same result: for `3.14.0-211.1.beta`, the same 157,808 files with the same permissions and contents. `tarcmp.py` compares two source tarballs entry by entry and ignores timestamps and archive order, because the compressed files themselves differ between GNU tar and xz versions even when the contents are the same.

The FreeBSD script, with depot_tools pinned, also reproduces the published `dart-sdk-3.13.5-src.tar.xz` itself: run on FreeBSD 15.1 in October 2026, it gave the same 156,456 entries, with no differences.
