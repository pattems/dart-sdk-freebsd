# The bootstrap SDK

Building the Dart SDK runs Dart programs: the front end, the snapshot generators, `dart2js` and the analyzer are written in Dart. So the build needs a working Dart SDK first, the way `lang/go` and `lang/rust` need a bootstrap compiler. Upstream only publishes SDKs for Linux, macOS and Windows, so the port uses a FreeBSD build of the SDK, published as a release asset here (`dart-sdk-<version>-bootstrap-freebsd15-<arch>.tar.xz`). It needs FreeBSD 14.5 or later, because it uses `FBSD_1.8` symbols.

Each new bootstrap is built on FreeBSD by the previous one, as described below. (The very first one had to come from Linux; [`initial-bootstrap/`](../initial-bootstrap/) describes how it was made.)

## Which SDK a release needs

Each Dart release pins the SDK its build uses in `DEPS` (`sdk_tag`), and that's a pre-release, often of the same minor version:

| Release | Builds with |
|---|---|
| 3.12.0 | 3.12.0-210.1.beta |
| 3.13.0 – 3.13.5 | 3.13.0-103.1.beta |
| 3.14.0 (beta) | 3.14.0-75.0.dev |

The in-tree packages set their minimum SDK to match, so the requirement is real: `pkg/dev_compiler` in 3.14 requires `^3.14.0-0`, which no 3.13 SDK satisfies. Unlike Go and Rust, a new minor release can't be built with the previous release's bootstrap. Patch releases (3.13.x) keep the same pin, so one bootstrap covers a whole minor version.

## Making a bootstrap for a new minor release

Each pinned SDK was itself built by an older one, so a new minor release can be reached from the current bootstrap by building the tags in between. Everything below runs on FreeBSD, without the Linux compatibility layer.

1. **Find the chain.** Walk back from the new release through each tag's `sdk_tag` in `DEPS` until reaching a pin that the current bootstrap can stand in for: no newer than it, and satisfying the in-tree packages' minimum SDK. For 3.14:

   ```
   3.14.0 betas     pin 3.14.0-75.0.dev
   3.14.0-75.0.dev  pins 3.13.0-272.0.dev; its packages need 3.13.0-107.0.dev or later
   3.13.5           (the current bootstrap) satisfies both
   ```

2. **Make each tag's source** with [`tools/make-dist.sh`](../tools/make-dist.sh). Pass the previous link in the chain as the host SDK (for the first tag, the current bootstrap); two `DEPS` hooks run it. The script fetches the git dependencies with `gclient` and downloads the few CIPD packages the source needs (DevTools and test data) over CIPD's HTTP API, since there's no FreeBSD `cipd` client.

3. **Port the patches** to each tag (`git cherry-pick` of `patches/<version>/`, resolving any conflicts) and export them as one `-p1` patch per tag.

4. **Build each tag** with the previous link's SDK as the host, using [`tools/build-bootstrap.sh`](../tools/build-bootstrap.sh). It refuses to run while the Linux compatibility layer is loaded, so the result can't depend on Linux binaries.

The last build in the chain is the new bootstrap.

### Tested with 3.14 (October 2026)

Starting from the published 3.13.5 bootstrap, on FreeBSD 15.1 amd64 with the Linux compatibility layer unloaded:

| Step | Host SDK | Result |
|---|---|---|
| Make the `3.14.0-211.1.beta` source | FreeBSD `3.14.0-75.0.dev` (for the hooks) | the same files, permissions and contents as upstream's Linux tooling produces ([details](../initial-bootstrap/README.md#the-3135-source-distfile)) |
| Build `3.14.0-75.0.dev` | the 3.13.5 bootstrap | `create_sdk` succeeds; `dart compile exe` produces working FreeBSD executables |
| Build `3.14.0-211.1.beta` | the `3.14.0-75.0.dev` SDK from the previous step | `create_sdk` succeeds; `dart compile exe` produces working FreeBSD executables |

All 26 patches applied to both tags. On `3.14.0-211.1.beta`, two needed small conflict fixes for nearby upstream changes: a new `#include` next to ours, and upstream's new MemorySanitizer wrappers for the `stat` functions, which the `/dev/fd` change now calls.

## aarch64

The 3.13.5 aarch64 bootstrap was cross-compiled on FreeBSD 15.1 amd64, not built natively. It's the port's source and patches, built with the amd64 bootstrap as the host SDK and these changes to the port's GN arguments:

```
host_cpu = "x64"
target_cpu = "arm64"
dart_target_arch = "arm64"
dart_snapshot_kind = "kernel"
```

The C and C++ compilers are the base system's clang, behind a wrapper that adds `--sysroot` (the `lib`, `usr/lib`, `usr/include` and `usr/libdata` directories of FreeBSD 15.1's arm64 `base.txz`) to aarch64 command lines only. Setting GN's `target_sysroot` instead also applies it to the host toolchain, which breaks the x64 build tools. `dart_snapshot_kind` is `kernel` because app-jit snapshots come from a training run, which can't run on a different CPU, so the bundled tools start a little more slowly than in a native build. As in the amd64 bootstrap, the `*.sym` files were removed and the AOT snapshots in `bin/snapshots` stripped.

It has only been tested in a FreeBSD 15.1 arm64 virtual machine under QEMU (Cortex-A72): it runs the build's Dart code, and `dart create`, `pub get`, `analyze`, `test` and `compile exe` work. A native build of the port on aarch64 hardware hasn't been done yet. Once one is, the next aarch64 bootstrap can be built natively like the amd64 one.
