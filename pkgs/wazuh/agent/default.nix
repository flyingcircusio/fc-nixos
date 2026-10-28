{
  autoconf,
  automake,
  bpftools,
  clang,
  cmake,
  curl,
  elfutils,
  expat,
  fetchFromGitHub,
  fetchurl,
  file,
  lib,
  libbfd,
  libbpf,
  libcap,
  libelf,
  libgcc,
  libtool,
  llvm,
  openssl,
  patchelf,
  perl,
  pkg-config,
  policycoreutils,
  python312,
  removeReferencesTo,
  stdenv,
  systemd,
  zlib,
  # Needed for makefile
  ps,
  ...
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "wazuh-agent";
  version = "4.14.5";

  enableParallelBuilding = true;

  src = fetchFromGitHub {
    owner = "wazuh";
    repo = "wazuh";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Vtld3DCp3OEFcevydZC6gZkL2ngbPsasBiyzBc5VRDY=";
  };

  dontConfigure = true;

  hardeningDisable = [
    "zerocallusedregs"
  ];

  # libdb (src/external/libdb) trips GCC >= 14's default errors for
  # incompatible-pointer-types and old-style-definition in its generated
  # configure/Makefile code. The flags only downgrade these two warnings;
  # injecting them via the cc wrapper works regardless of how libdb's
  # internal makefiles plumb CFLAGS.
  env.NIX_CFLAGS_COMPILE = "-Wno-error=incompatible-pointer-types -Wno-error=old-style-definition";

  nativeBuildInputs = [
    autoconf
    automake
    clang
    cmake
    curl
    file # Required by configure scripts (e.g., popt)
    patchelf
    perl
    ps
    pkg-config
    policycoreutils
    python312
    python312.pkgs.setuptools
    removeReferencesTo
    zlib
  ];

  buildInputs = [
    elfutils
    expat
    libbfd
    libbpf
    libcap
    libelf
    libtool
    llvm
    openssl
  ];

  makeFlags = [
    "-C src"
    "TARGET=agent"
    "INSTALLDIR=$out"
  ];

  patches = [
    ./01-makefile-patch.patch
    ./02-libbpf-bootstrap.patch
    ./03-cstdint-include.patch
    ./04-snap-onerror-signature.patch
    ./05-bpf-helpers-libbpf-1_7.patch
    ./06-privsep-systemd-user.patch
    ./07-wazuh-home-env.patch
  ];

  postUnpack =
    let
      inherit (finalAttrs.passthru) libbpf_bootstrap_deps externalDependencies wazuh-http-request;
    in
    ''
      pushd $sourceRoot

      mkdir -p src/external
      ${lib.strings.concatMapStringsSep "\n" (
        dep: "tar -xzf ${dep} -C src/external"
      ) externalDependencies}

      echo 'grabbing libbpf-bootstrap submodules...'
      mkdir -p src/external/libbpf-bootstrap/src
      cp -r --preserve=timestamps --reflink=auto -- ${libbpf_bootstrap_deps.bootstrap}/* src/external/libbpf-bootstrap

      echo 'extracting Wazuh CMakeLists.txt for libbpf-bootstrap...'
      # Tarball stores members with ./ prefix (./libbpf-bootstrap/CMakeLists.txt);
      # strip-components=2 drops both ./ and libbpf-bootstrap/ so files land directly in target.
      # The archive contains only CMakeLists.txt and tools/, so extracting all is safe.
      tar -xzf ${libbpf_bootstrap_deps.cmakeLists} -C src/external/libbpf-bootstrap --strip-components=2

      echo 'grabbing modern_bpf_c...'
      cp ${libbpf_bootstrap_deps.modern_bpf_c} src/external/libbpf-bootstrap/src/modern.bpf.c

      echo 'grabbing wazuh-http-request...'
      mkdir -p src/shared_modules/http-request
      cp -r --preserve=timestamps --reflink=auto -- ${wazuh-http-request}/* src/shared_modules/http-request
      popd
    '';

  prePatch = ''
    substituteInPlace src/init/wazuh-server.sh \
      --replace-fail "cd ''${LOCAL}" ""

    substituteInPlace src/external/audit-userspace/autogen.sh \
      --replace-fail "cp INSTALL.tmp INSTALL" ""

    substituteInPlace src/init/inst-functions.sh \
      --replace-fail "WAZUH_GROUP='wazuh'" "WAZUH_GROUP='nixbld'" \
      --replace-fail "WAZUH_USER='wazuh'" "WAZUH_USER='nixbld'"

    substituteInPlace src/external/libbpf-bootstrap/CMakeLists.txt \
      --replace-fail "/usr/bin/clang" "${clang}/bin/clang" \
      --replace-fail 'set(BPFOBJECT_BPFTOOL_EXE ''${CMAKE_CURRENT_BINARY_DIR}/bpftool/bootstrap/bpftool)' 'set(BPFOBJECT_BPFTOOL_EXE ${bpftools}/bin/bpftool)'

    cat << EOF > "etc/preloaded-vars.conf"
    USER_LANGUAGE="en"
    USER_NO_STOP="y"
    USER_INSTALL_TYPE="agent"
    USER_DIR="$out"
    USER_DELETE_DIR="n"
    USER_ENABLE_ACTIVE_RESPONSE="y"
    USER_ENABLE_SYSCHECK="n"
    USER_ENABLE_ROOTCHECK="y"
    USER_AGENT_SERVER_IP=127.0.0.1
    USER_CA_STORE="n"
    EOF
  '';

  # eBPF configuration for the vendored libbpf-bootstrap CMakeLists: disable
  # the network download of modern.bpf.c (provided by postUnpack/fetchurl)
  # and add the C standard/warning flags for the bpf_object target —
  # GCC/clang >= 15 turn implicit-function-declaration and int-conversion
  # into errors. Applied in postPatch — AFTER the patch files — so
  # 02-libbpf-bootstrap.patch matches unmodified upstream context.
  postPatch = ''
    substituteInPlace src/external/libbpf-bootstrap/CMakeLists.txt \
      --replace-fail 'file(DOWNLOAD ''${FILE_URL} ''${DEST_PATH})' '# file(DOWNLOAD ''${FILE_URL} ''${DEST_PATH})' \
      --replace-fail 'file(SIZE ''${DEST_PATH} FILE_SIZE)' '# file(SIZE ''${DEST_PATH} FILE_SIZE)' \
      --replace-fail 'bpf_object(modern src/modern.bpf.c)' 'set(CMAKE_C_FLAGS "''${CMAKE_C_FLAGS} -std=gnu17 -Wno-error=implicit-function-declaration -Wno-error=int-conversion")
    bpf_object(modern src/modern.bpf.c)'
  '';

  preBuild = ''
    export CXX=${stdenv.cc}/bin/c++
    make -C src TARGET=agent settings
    make -C src TARGET=agent INSTALLDIR=$out deps
  '';

  installPhase = ''
    mkdir -p $out/{bin,etc/shared,queue,var,wodles,logs,lib,tmp,agentless,active-response}

    substituteInPlace install.sh \
      --replace-fail "Xroot" "Xnixbld"
    chmod u+x install.sh

    INSTALLDIR=$out USER_DIR=$out ./install.sh binary-install

    substituteInPlace $out/bin/wazuh-control \
      --replace-fail "cd ''${LOCAL}" "#"

    chmod u+x $out/bin/* $out/active-response/bin/*
  '';

  fixupPhase = ''
    remove-references-to -t ${libgcc.out} $out/lib/*

    patchelf --add-rpath ${systemd}/lib $out/bin/wazuh-logcollector
  '';

  passthru = {
    dependencyVersion = "51";

    # Data list from external-dependencies.nix is mapped to fetchurl calls here
    # (instead of pre-applied fetchers inside the list — list literals do not
    # apply functions) so the URL scheme and dependencyVersion stay in one
    # place and re-resolve when dependencyVersion is overridden.
    externalDependencies = map (
      dep:
      fetchurl {
        url = "https://packages.wazuh.com/deps/${finalAttrs.passthru.dependencyVersion}/libraries/sources/${dep.name}.tar.gz";
        inherit (dep) hash;
      }
    ) (import ./dependencies/external-dependencies.nix);

    wazuh-http-request = fetchFromGitHub {
      owner = "wazuh";
      repo = "wazuh-http-request";
      rev = "75384783d339a817b8d8f13f778051a878d642a6";
      hash = "sha256-yCKxwzG65BB3Cr1gEkX4qxbGCjG5zzJpq9di5L1couU=";
    };
    libbpf_bootstrap_deps = {
      # GitHub version with submodules (libbpf/, bpftool/, vmlinux.h/, tools/)
      bootstrap = fetchFromGitHub {
        owner = "libbpf";
        repo = "libbpf-bootstrap";
        rev = "aa18cc0d8fc8ef4104fb74d218ae6a20cf6eb176";
        hash = "sha256-ggIDf/I4QlSypFpsRibsdWd9bSevC2mfyEenlYZQdqI=";
        fetchSubmodules = true;
      };
      # Wazuh's customized CMakeLists.txt (not in upstream libbpf-bootstrap)
      cmakeLists = fetchurl {
        url = "https://packages.wazuh.com/deps/${finalAttrs.passthru.dependencyVersion}/libraries/sources/libbpf-bootstrap.tar.gz";
        hash = "sha256-b3bQXFpDWCBLnfoKNy8lfROP/4QC/cUkSRNdq5mt8zY=";
      };
      modern_bpf_c = fetchurl {
        url = "https://raw.githubusercontent.com/wazuh/wazuh/v${finalAttrs.version}/src/syscheckd/src/ebpf/src/modern.bpf.c";
        hash = "sha256-D7NPWwrBblP43U7DoBgZewo4wmn3HWGr14wU85+fOC8=";
      };
    };
  };

  meta = {
    description = "Wazuh agent for NixOS";
    homepage = "https://wazuh.com";
    license = [ lib.licenses.gpl2Only ];
    platforms = [ "x86_64-linux" ];
  };
})
