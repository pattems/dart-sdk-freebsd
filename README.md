# dart-sdk-freebsd

A FreeBSD port of the [Dart SDK](https://dart.dev/), `lang/dart`. It builds the full SDK natively on FreeBSD: the VM, the `dart` tool (`create`, `pub`, `analyze`, `format`, `test`, `run`) and the compilers (`dart compile exe`, `js` and `wasm`).

**Status:** Dart 3.13.5 on FreeBSD 15.1 and 14.5. On amd64 the port builds and passes `poudriere testport`, but it isn't in the FreeBSD ports tree yet. aarch64 is untested: its bootstrap was cross-compiled and has only run under emulation (see [`docs/bootstrap.md`](docs/bootstrap.md#aarch64)). Reports from aarch64 hardware are welcome.

## Installing

Use `lang/dart` from this repository as a ports overlay. With poudriere:

```sh
git clone https://github.com/pattems/dart-sdk-freebsd.git /usr/local/dart-sdk-freebsd
poudriere ports -c -p dart -m null -M /usr/local/dart-sdk-freebsd
poudriere bulk -j <jail> -O dart lang/dart
```

Or copy `lang/dart` into a ports tree and run `make install` there.

The SDK installs to `/usr/local/lib/dart`, with `dart` and `dartaotruntime` linked into `/usr/local/bin`.

## What the port downloads

The port needs two files: the Dart SDK's source, and an already-built Dart SDK to run the Dart parts of the build (like the bootstrap compiler `lang/go` and `lang/rust` use). Dart publishes neither a source tarball nor FreeBSD binaries, so both come from this repository's [releases](https://github.com/pattems/dart-sdk-freebsd/releases):

- **`dart-sdk-<version>-src.tar.xz`, the source:** the Dart SDK at the release tag, with the dependencies from its `DEPS` file, made on FreeBSD by [`tools/make-dist.sh`](tools/make-dist.sh). The prebuilt Linux and macOS toolchains are left out; the port uses FreeBSD's clang, gn and ninja.
- **`dart-sdk-<version>-bootstrap-freebsd15-<arch>.tar.xz`, the bootstrap:** a compiled Dart SDK for FreeBSD, one per architecture (`amd64`, `aarch64`). The build runs it but doesn't install it. Each new one is built on FreeBSD by the previous one; [`docs/bootstrap.md`](docs/bootstrap.md) explains how.

The very first bootstrap, and the 3.13.5 source distfile, came from Linux; [`initial-bootstrap/`](initial-bootstrap/) records how.

## The patches

The port applies its changes from [`lang/dart/files/`](lang/dart/files/): ordinary `make makepatch` patches, one per patched source file.

The same changes are also in [`patches/3.13.5/`](patches/3.13.5/) as a `git format-patch` series, one change per commit, with a commit message explaining each one. That series is easier to read and review; the port doesn't use it. [`tools/to-makepatch.sh`](tools/to-makepatch.sh) regenerates `lang/dart/files/` from it.

FreeBSD is built as a variant of Linux, which the Dart VM already does (`__FreeBSD__` maps to `DART_HOST_OS_LINUX`). The FreeBSD-specific changes are guarded so they don't affect other platforms. The series is written to be sent to the Dart project; versions rebased onto Dart's current `main` are on [`pattems/dart-sdk`](https://github.com/pattems/dart-sdk/branches).

## Tests

Dart's VM test suites (`vm`, `standalone`, `ffi`, `lib`, `corelib` and `language`) were run on FreeBSD 15.1 with the port's patches: of 12,629 tests, 12,524 pass and 105 fail. 100 of the failures also fail on Linux with unpatched Dart 3.13.5. The other five fail only on FreeBSD:

| Test | Why it fails on FreeBSD |
|---|---|
| `standalone/io/unix_socket_test` | Uses Linux's abstract socket namespace (`@name`) |
| `standalone/io/raw_datagram_socket_test` | Sends 64 KB UDP datagrams; FreeBSD's default limit is 9,216 bytes (see below) |
| `standalone/io/regress_21987_test` | Reads `/proc/self/exe` |
| `vm/dart/exported_symbols_test` | Expects libc++ to be linked statically; FreeBSD links the system libc++ dynamically |
| `vm/dart/thread_priority_linux_test` | `--worker-thread-priority` isn't supported on FreeBSD and exits by design |

## Notes for Dart programs

Dart programs see FreeBSD as Linux: `Platform.operatingSystem` returns `"linux"` and `Platform.isLinux` is `true`. That's how the Dart VM's source already classifies FreeBSD, and the port keeps it so, because most code that checks for Linux only needs a POSIX system and works on FreeBSD too. To tell the two apart, check `Platform.operatingSystemVersion`, which starts with `FreeBSD`.

Code that assumes more than POSIX can trip over the real differences:

- Packages that load `libc.so.6` by name through `dart:ffi` fail, because FreeBSD's C library is `libc.so.7`. `DynamicLibrary.process()` works on both.
- UDP datagrams are limited to 9,216 bytes by default, while Linux allows about 64 KB. To send and receive larger ones, raise `net.inet.udp.maxdgram` and `net.inet.udp.recvspace` (the package's install message has the details).

## License

The port files and tools in this repository are under the BSD 2-Clause license (see [LICENSE](LICENSE)). The patches modify the Dart SDK and are under its [BSD 3-Clause license](https://github.com/dart-lang/sdk/blob/main/LICENSE).
