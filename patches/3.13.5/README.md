# Patches for Dart SDK 3.13.5

The port doesn't use these files. It applies the `make makepatch` patches in [`lang/dart/files/`](../../lang/dart/files/), one per patched source file.

This folder has the same changes as a `git format-patch` series, for reading and review: one change per commit, each with a commit message explaining it. [`tools/to-makepatch.sh`](../../tools/to-makepatch.sh) generates the port's patches from it. The series applies with `git am` or `patch -p1` from the top of the SDK source tree (the `sdk/` directory of a `gclient` checkout, or the source distfile), in file-name order.

| Files | What |
|---|---|
| `patch-0000-*` | Upstream commits that 3.13.5 doesn't have yet but the series depends on |
| `patch-0001` … `patch-0025` | The FreeBSD changes |
| `patch-1001-perfetto-*` | Perfetto's upstream FreeBSD support, backported to the Perfetto version Dart 3.13.5 pins (`third_party/perfetto/src`) |
| `patch-1002-zlib-*` | ARMv8 CRC32/PMULL detection for Chromium's zlib on FreeBSD/arm64 (`third_party/zlib`) |

## How the changes are made

The Dart VM already treats FreeBSD as a Linux variant: `runtime/platform/globals.h` maps `__FreeBSD__` to `DART_HOST_OS_LINUX`. The series keeps that. FreeBSD builds the `*_linux.cc` files, and the places where FreeBSD differs from Linux are guarded with `#if defined(__FreeBSD__)` (or `current_os == "freebsd"` in GN), so those changes don't affect other platforms. Where FreeBSD has no epoll, it uses the kqueue code that macOS already uses.

Four patches are general fixes that apply on every platform: 0001 (building without Perfetto), 0002 (reading back boolean socket options), 0016 (moving the macOS signal-number table into a shared header, with no behavior change) and 0024 (accepting musl's and FreeBSD's loader error messages in two FFI tests).

Nothing here changes Dart's public API. `Platform.operatingSystem` still returns `"linux"` on FreeBSD.

## Versions for upstream

Patches 0001–0025 are written to be sent to the Dart project. Versions rebased onto Dart's current `main`, one branch per change, are on [`pattems/dart-sdk`](https://github.com/pattems/dart-sdk/branches): the `freebsd/*` branches, plus `fix-build-without-perfetto`, `nonzero-bool-sockopt`, `process-signal-map-header` and `ffi-test-loader-errors` for the changes that aren't specific to FreeBSD. `freebsd/all` has all of them together. Current `main` needs one change that 3.13.5 doesn't (`freebsd/host-arch-amd64`).
