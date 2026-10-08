PORTNAME=	dart
DISTVERSION=	3.13.5
CATEGORIES=	lang
MASTER_SITES=	https://github.com/pattems/dart-sdk-freebsd/releases/download/${DISTVERSION}/
DISTFILES=	dart-sdk-${DISTVERSION}-src${EXTRACT_SUFX} \
		dart-sdk-${BOOTSTRAP_VERSION}-bootstrap-freebsd15-${ARCH}${EXTRACT_SUFX}
DIST_SUBDIR=	dart

MAINTAINER=	patrick@crandol.com
COMMENT=	Dart programming language SDK
WWW=		https://dart.dev/

LICENSE=	BSD3CLAUSE
LICENSE_FILE=	${WRKSRC}/LICENSE

ONLY_FOR_ARCHS=	amd64
ONLY_FOR_ARCHS_REASON=	no bootstrap SDK for other architectures yet

BUILD_DEPENDS=	gn:devel/gn

USES=		ninja:build python:build tar:xz
# The build scripts ask git for version information and cope with git
# failing, but not with it being absent.
BINARY_ALIAS=	git=false python3=${PYTHON_CMD}

# The source distfile is a gclient checkout of the release tag without the
# prebuilt Linux toolchains; see make-dist.sh. The bootstrap is a FreeBSD
# build of the Dart SDK, used to run the Dart parts of the build.
BOOTSTRAP_VERSION=	3.13.5

WRKSRC=		${WRKDIR}/dart-sdk-${DISTVERSION}

# Same arguments as tools/gn.py --mode release --arch x64, except for those
# that need a git checkout (verify_sdk_hash, dart_version_git_info).
# Perfetto is off by default on FreeBSD; the patch-third__party_perfetto_*
# files backport Perfetto's FreeBSD support so it can be enabled.
GN_ARGS=	target_os="freebsd" \
		host_cpu="x64" \
		target_cpu="x64" \
		dart_target_arch="x64" \
		dart_use_compressed_pointers=false \
		dart_use_crashpad=false \
		dart_snapshot_kind="app-jit" \
		is_debug=false \
		is_release=true \
		is_product=false \
		dart_debug=false \
		dart_runtime_mode="develop" \
		is_clang=true \
		dart_stripped_binary="exe.stripped/dart" \
		dartvm_stripped_binary="exe.stripped/dartvm" \
		dart_aotruntime_stripped_binary="exe.stripped/dartaotruntime_product" \
		gen_snapshot_stripped_binary="exe.stripped/gen_snapshot_product" \
		analyze_snapshot_binary="exe.stripped/analyze_snapshot" \
		wasm_opt_stripped_binary="exe.stripped/wasm-opt" \
		use_rbe=false \
		verify_sdk_hash=false \
		dart_version_git_info=false \
		dart_support_perfetto=true

MAKE_ENV=	HOME=${WRKDIR}

.include <bsd.port.options.mk>

.if ${OSVERSION} < 1405000
IGNORE=		requires FreeBSD 14.5 or later
.endif

SDKDIR=		lib/dart
SDK_PROGRAMS=	bin/dart bin/dartaotruntime bin/dartvm bin/utils/gen_snapshot \
		bin/utils/wasm-opt

post-extract:
	${MV} ${WRKDIR}/dart-sdk ${WRKSRC}/tools/sdks/dart-sdk

do-configure:
	${MKDIR} ${WRKSRC}/out/release
	@${RM} ${WRKSRC}/out/release/args.gn
.for a in ${GN_ARGS}
	@${ECHO_CMD} '${a}' >> ${WRKSRC}/out/release/args.gn
.endfor
	cd ${WRKSRC} && ${SETENV} ${MAKE_ENV} gn gen out/release

do-build:
	cd ${WRKSRC} && ${SETENV} ${MAKE_ENV} \
		ninja -C out/release -j ${MAKE_JOBS_NUMBER} create_sdk

do-install:
	${MKDIR} ${STAGEDIR}${PREFIX}/${SDKDIR}
	cd ${WRKSRC}/out/release/dart-sdk && \
		${COPYTREE_SHARE} . ${STAGEDIR}${PREFIX}/${SDKDIR}
	${FIND} ${STAGEDIR}${PREFIX}/${SDKDIR} -name '*.sym' -delete
	# The SDK already contains the stripped binaries (see *_stripped_binary).
	cd ${STAGEDIR}${PREFIX}/${SDKDIR} && ${CHMOD} 555 ${SDK_PROGRAMS}
	${RLN} ${STAGEDIR}${PREFIX}/${SDKDIR}/bin/dart ${STAGEDIR}${PREFIX}/bin/dart
	${RLN} ${STAGEDIR}${PREFIX}/${SDKDIR}/bin/dartaotruntime \
		${STAGEDIR}${PREFIX}/bin/dartaotruntime

.include <bsd.port.mk>
