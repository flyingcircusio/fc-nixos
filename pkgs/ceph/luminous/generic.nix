{ stdenv, lib, ensureNewerSourcesHook, cmake, pkgconfig
, which, git
, boost, python2Packages
, libxml2, zlib
, openldap, lttng-ust
, babeltrace, gperf
, cunit, snappy
, makeWrapper
, fetchpatch

# Optional Dependencies
, yasm ? null, fcgi ? null, expat ? null
, curl ? null, fuse ? null
, libedit ? null, libatomic_ops ? null, kinetic-cpp-client ? null
, libs3 ? null

# Mallocs
, jemalloc ? null, gperftools ? null

# Crypto Dependencies
, cryptopp ? null
, nss ? null, nspr ? null

# Linux Only Dependencies
, linuxHeaders, libuuid, udev, keyutils, libaio ? null, libxfs ? null
, zfs ? null

# building docs requires python3
, withDocs ? true, python3ForDocBuilding

# Version specific arguments
, version, src ? [], buildInputs ? []
, ...
}:

# We must have one crypto library
assert cryptopp != null || (nss != null && nspr != null);

with stdenv;
with lib;
let

  shouldUsePkg = pkg_: let pkg = (builtins.tryEval pkg_).value;
    in if pkg.meta.available or false then pkg else null;

  optYasm = shouldUsePkg yasm;
  optFcgi = shouldUsePkg fcgi;
  optExpat = shouldUsePkg expat;
  optCurl = shouldUsePkg curl;
  optFuse = shouldUsePkg fuse;
  optLibedit = shouldUsePkg libedit;
  optLibatomic_ops = shouldUsePkg libatomic_ops;
  optKinetic-cpp-client = shouldUsePkg kinetic-cpp-client;
  optLibs3 = if versionAtLeast version "10.0.0" then null else shouldUsePkg libs3;

  optJemalloc = shouldUsePkg jemalloc;
  optGperftools = shouldUsePkg gperftools;

  optCryptopp = shouldUsePkg cryptopp;
  optNss = shouldUsePkg nss;
  optNspr = shouldUsePkg nspr;

  optLibaio = shouldUsePkg libaio;
  optLibxfs = shouldUsePkg libxfs;
  optZfs = shouldUsePkg zfs;

  hasRadosgw = optFcgi != null && optExpat != null && optCurl != null && optLibedit != null;


  # TODO: Reenable when kinetic support is fixed
  #hasKinetic = versionAtLeast version "9.0.0" && optKinetic-cpp-client != null;
  hasKinetic = false;

  # Malloc implementation (can be jemalloc, tcmalloc or null)
  malloc = if optJemalloc != null then optJemalloc else optGperftools;

  # We prefer nss over cryptopp
  cryptoStr = if optNss != null && optNspr != null then "nss" else
    if optCryptopp != null then "cryptopp" else "none";
  cryptoLibsMap = {
    nss = [ optNss optNspr ];
    cryptopp = [ optCryptopp ];
    none = [ ];
  };

  ceph-python-env = python2Packages.python.buildEnv.override {
    extraLibs = (ps:[
      ps.sphinx
      ps.flask
      ps.cython
      ps.setuptools
      ps.pip
      # Libraries needed by the python tools
      ps.Mako
      ps.pecan
      ps.prettytable
      ps.webob
      ps.cherrypy
    ]) python2Packages;
    # backport namespace collisions, see https://github.com/NixOS/nixpkgs/issues/22319#issuecomment-276913527
    ignoreCollisions = true;
  };

  # see admin/doc-requirements.txt in sources
  docs-python-env = python3ForDocBuilding.withPackages (ps: [
    ps.sphinx
    ps.sphinx-ditaa
    ps.breathe
    ps.pyyaml
    ps.pip
    ps.cython
  ]);

in
stdenv.mkDerivation {
  pname = "ceph";
  inherit version;

  inherit src;

  patches = [
    # fix duplicate test names that are confusing GoogleTests macro expansion
    (fetchpatch {
      url = "https://github.com/ceph/ceph/pull/43491.patch";
      sha256 = "sha256-ck6C5mdimrhBC600fMsmL6ToUXiM9FTzl9fSxwnYw9s=";
    })

    # doc state machine graph generator, weirdly this python3 port is in most
    # Luminous releases but not in this one.
    (fetchpatch {
      url = "https://github.com/ceph/ceph/commit/965f20d8ee08b9b917ccfac59e5346eaf8c7f077.patch";
      sha256 = "sha256-kbdkx3n4ZAjWA9H5JYQEoZhGvxCjHcFYDmA6XKwcQFk=";
    })
    (fetchpatch {
      url = "https://github.com/ceph/ceph/commit/61e7bcded852e90e6249ab0f3c37ec2688537c83.patch";
      sha256 = "sha256-PxPtE3aOTq6SFTUMIz7/gJrpQCXnB+HcW68CcftUZN4=";
    })
  ] ++ optionals stdenv.isLinux [
    ./0002-fix-absolute-include-path.patch
  ];

  nativeBuildInputs = [
    cmake
    pkgconfig which git python2Packages.wrapPython makeWrapper
    (ensureNewerSourcesHook { year = "1980"; })
  ];

  buildInputs = buildInputs ++ cryptoLibsMap.${cryptoStr} ++ [
    boost ceph-python-env libxml2 optYasm optLibatomic_ops optLibs3
    malloc zlib openldap lttng-ust babeltrace gperf cunit
    snappy
  ] ++ optionals stdenv.isLinux [
    linuxHeaders libuuid udev keyutils optLibaio optLibxfs optZfs
  ] ++ optionals hasRadosgw [
    optFcgi optExpat optCurl optFuse optLibedit
  ] ++ optionals hasKinetic [
    optKinetic-cpp-client
  ];


  preConfigure =''
    # rip off submodule that interfer with system libs
	rm -rf src/boost

	# require LD_LIBRARY_PATH for cython to find internal dep
	export LD_LIBRARY_PATH="$PWD/build/lib:$LD_LIBRARY_PATH"

	# requires setuptools due to embedded in-cmake setup.py usage
	export PYTHONPATH="${python2Packages.setuptools}/lib/python*/site-packages/:$PYTHONPATH"
  '';

  cmakeFlags = [
    "-DENABLE_GIT_VERSION=OFF"
    "-DWITH_SYSTEM_BOOST=ON"
    # using an unpatched system rocksdb might break bluestore, see https://github.com/NixOS/nixpkgs/pull/113137/
    "-DWITH_SYSTEM_ROCKSDB=OFF"
    "-DWITH_LEVELDB=OFF"

    # enforce shared lib
    "-DBUILD_SHARED_LIBS=ON"

    # disable cephfs, cmake build broken for now
    "-DWITH_CEPHFS=OFF"
    "-DWITH_LIBCEPHFS=OFF"

    # required for glibc>=2.32
    "-DWITH_REENTRANT_STRSIGNAL=ON"

    # explicitly set which python versions to build against
    # ceph-mgr supports *only* python2, so for now use this as the only python version
    "-DWITH_PYTHON2=ON"
    # FIXME: It might be possible to *additionally* build python3 bindings for some ceph components
    # like rbd, rgw
    "-DWITH_PYTHON3=OFF"
  ];

  # build documentation:
  # build script adapted from ceph sources admin/build-doc, but simplified and without virtualenv
  preBuild = if withDocs then ''
    # save old vars to be restored after this phase
    OLD_LD_LIBRARY_PATH=$LD_LIBRARY_PATH
    OLD_PYTHONPATH=$PYTHONPATH
    OLD_PATH=$PATH



    TOPDIR="$NIX_BUILD_TOP/$sourceRoot"
    ls $TOPDIR
    install -d -m0755 $TOPDIR/build-doc
    cat $TOPDIR/src/osd/PG.h $TOPDIR/src/osd/PG.cc | ${docs-python-env}/bin/python3 $TOPDIR/doc/scripts/gen_state_diagram.py > $TOPDIR/doc/dev/peering_graph.generated.dot

    pushd $TOPDIR/build-doc

    vdir="$TOPDIR/build-doc/this-is-not-a-virtualenv"

    install -d -m0755 \
      $TOPDIR/build-doc/output/html \
      $TOPDIR/build-doc/output/man

    # To avoid having to build librbd to build the Python bindings to build the docs,
    # create a dummy librbd.so that allows the module to be imported by sphinx.
    # the module are imported by the "automodule::" directive.
    mkdir -p $vdir/lib
    export LD_LIBRARY_PATH="$vdir/lib"
    export PYTHONPATH=$TOPDIR/src/pybind

    # Tells pip to put packages into $PIP_PREFIX instead of the usual locations.
    # See https://pip.pypa.io/en/stable/user_guide/#environment-variables.
    export PIP_PREFIX=$vdir/
    export PYTHONPATH="$PIP_PREFIX/${docs-python-env.sitePackages}:$PYTHONPATH"
    export PATH="$PIP_PREFIX/bin:$PATH"

    set -x

    # FIXME(sileht): I dunno how to pass the include-dirs correctly with pip
    # for build_ext step, it should be:
    # --global-option=build_ext --global-option="--cython-include-dirs $TOPDIR/src/pybind/rados/"
    # but that doesn't work, so copying the file in the rbd module directly, that's ok for docs
    # modification: skip cephfs as it causes problems when building docs and we don't use it
    for bind in rados rbd rgw; do
        if [ ''${bind} != rados ]; then
            cp -f $TOPDIR/src/pybind/rados/rados.pxd $TOPDIR/src/pybind/''${bind}/
        fi
        ln -sf lib''${bind}.so.1 $vdir/lib/lib''${bind}.so
        gcc -shared -o $vdir/lib/lib''${bind}.so.1 -xc /dev/null
        BUILD_DOC=1 \
            CFLAGS="-iquote$TOPDIR/src/include" \
            CPPFLAGS="-iquote$TOPDIR/src/include" \
            LDFLAGS="-L$vdir/lib -Wl,--no-as-needed" \
            ${docs-python-env}/bin/pip install $TOPDIR/src/pybind/''${bind}
        # rgwfile_version(), librgw_create(), rgw_mount()
        echo "current bind: ''${bind}, vdir: $vdir, pwd: $(pwd)"
        echo "about to run command: nm $vdir/lib/python*/*-packages/''${bind}.so | grep -E \"U (lib)?''${bind}\" | awk '{ print \"void \"$2\"(void) {}\" }' | gcc -shared -o $vdir/lib/lib''${bind}.so.1 -xc -"
        nm $vdir/lib/python*/*-packages/''${bind}.*.so | grep -E "U (lib)?''${bind}" | \
            awk '{ print "void "$2"(void) {}" }' | \
            gcc -shared -o $vdir/lib/lib''${bind}.so.1 -xc -
        echo "statuspoint 2"
        if [ ''${bind} != rados ]; then
            rm -f $TOPDIR/src/pybind/''${bind}/rados.pxd
        fi
        echo "statuspoint 3"
    done

    echo "statuspoint 4"
    if [ -z "$@" ]; then
        sphinx_targets="html man"
    else
        sphinx_targets=$@
    fi
    echo "statuspoint 5"
    for target in $sphinx_targets; do
        builder=$target
        case $target in
            html)
                builder=dirhtml
                ;;
            man)
                extra_opt="-t man"
                ;;
        esac
        ${docs-python-env}/bin/sphinx-build -a -b $builder $extra_opt -d doctrees \
                              $TOPDIR/doc $TOPDIR/build-doc/output/$target
    done

    # see result
    ls -R

    # restore old vars
    export LD_LIBRARY_PATH=$OLD_LD_LIBRARY_PATH
    export PYTHONPATH=$OLD_PYTHONPATH
    export PATH=$OLD_PATH
    unset PIP_PREFIX

    popd
    ''
    else "";

  postFixup = ''
    wrapPythonPrograms
    wrapProgram $out/bin/ceph-mgr --set PYTHONPATH $out/${python2Packages.python.sitePackages}
  '';

  enableParallelBuilding = true;

  outputs = [ "out" "dev" "lib" "doc" ];

  meta = {
    homepage = https://ceph.com/;
    description = "Distributed storage system";
    license = licenses.lgpl21;
    maintainers = with maintainers; [ theuni ];
    platforms = platforms.unix;
  };

  passthru.version = version;
}
