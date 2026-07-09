{
  version,
  src,
  ceph_client,
  coreutils,
  dosfstools,
  fc-ceph,
  fetchFromGitHub,
  file,
  gnused,
  gptfdisk,
  iproute2,
  lib,
  libceph,
  openssh,
  parted,
  procps,
  python3Packages,
  qemu_ceph,
  stdenv,
  strace,
  systemd,
  util-linux,
  xfsprogs,
  rustPlatform,
}:

let
  # Python must be the same as the one used by Ceph
  py = python3Packages.override {
    overrides =
      pyself: pysuper:
      let
        pydanticVersion = "2.13.4";
        pydanticSource = fetchFromGitHub {
          owner = "pydantic";
          repo = "pydantic";
          tag = "v${pydanticVersion}";
          hash = "sha256-G4Xo6BF6tOn4g/qG3RNDP3/+lYnCOuw3AB1OrVOGcSA=";
        };
      in
      {
        pydantic = pysuper.pydantic.overrideAttrs rec {
          src = pydanticSource;
          disabledTestPaths = pysuper.pydantic.disabledTestPaths ++ [
            # symlink to pydantic-core tests, can't be run here due to
            # dependencies.
            "tests/pydantic_core"
          ];
        };

        pydantic-core = pysuper.pydantic-core.overrideAttrs rec {
          version = "2.46.4";
          src = pydanticSource;
          sourceRoot = "${src.name}/pydantic-core";
          cargoDeps = rustPlatform.fetchCargoVendor {
            inherit src version;
            pname = "pydantic-core";
            hash = "sha256-5L317YTV7/Bc/YJLLzc745oJntiYkcZupdeUxiQwcOU=";
          };
        };
      };
  };

  # unreleased version
  py_consulate = py.buildPythonPackage rec {
    pname = "consulate";
    version = "1.1.0"; # unreleased version
    src = fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "consulate";
      rev = "90e46a4f307e281bf0e050d510fa367fd2826a2f";
      sha256 = "sha256-dt2hKcCtsGx5mtqyd83eTMhFRKjtqK/CcCGBy6ShNk8=";
    };
    doCheck = false; # tests require a running Consul via Docker
    pyproject = true;
    build-system = [ py.setuptools ];
    propagatedBuildInputs = [
      py.requests
    ];
    meta = with lib; {
      description = "Consulate is a Python client library and set of application for the Consul service discovery and configuration system.
";
      homepage = "https://pypi.org/project/consulate/";
      license = licenses.publicDomain;
    };
  };

in
# We use buildPythonPackage instead of buildPythonApplication
# to assist using this in a mixed buildEnv for external unit testing.
py.buildPythonPackage (finalAttrs: {
  inherit version src;

  name = "fc.qemu-${version}";

  dontStrip = true;

  pyproject = true;

  propagatedBuildInputs = [
    coreutils
    dosfstools
    gnused
    gptfdisk
    iproute2
    parted
    qemu_ceph
    systemd
    util-linux
    xfsprogs
    py.requests
    py.colorama
    py.structlog
    py_consulate
    py.psutil
    py.pydantic
    py.pyyaml
    py.setuptools
    py.websockets
    ceph_client
  ];

  passthru = {
    inherit py;
    # need to be defined here to keep them overridable *and* consistent,
    # because `buildPythonPackages` messes with `nativeCheckInputs`,
    nativeCheckInputs = [
      file
      openssh
      py.pytest_patterns
      py.pytest
      py.pytest-xdist
      py.pytest-cov
      py.pytest-timeout
      py.mock
      fc-ceph
      # Allow passing through to pytest in the NixOS test.
      (py.buildPythonPackage rec {
        pname = "pytest-flakefinder";
        version = "1.1.0";

        src = py.fetchPypi {
          inherit pname version;
          hash = "sha256-4kEqGSC9uOeQh4OyCz1X6drVkMw5qT6Flv/dSTtAPg4=";
        };

        pyproject = true;
        build-system = [ py.setuptools ];
        propagatedBuildInputs = [ py.pytest ];

        meta = {
          description = "Runs tests multiple times to expose flakiness.";
          homepage = "https://github.com/dropbox/pytest-flakefinder";
        };
      })
    ];
  };

  postInstall = ''
    cp -Pr $src/share $out/share
  '';

  nativeCheckInputs = finalAttrs.passthru.nativeCheckInputs;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    PATH="${lib.makeBinPath finalAttrs.propagatedBuildInputs}:$PATH" pytest -vv -m "unit"
    runHook postCheck
  '';

})
