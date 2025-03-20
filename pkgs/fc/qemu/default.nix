{
  version,
  src,
  pkgs,
  python3Packages,
  lib,
  libceph,
  ceph_client,
  fc-ceph,
  fetchFromGitHub,
  utillinux,
  coreutils,
  qemu_ceph,
  stdenv,
  gptfdisk,
  parted,
  xfsprogs,
  procps,
  strace,
  file,
  systemd,
  py_pytest_patterns
}:

let
  # Python must be the same as the one used by Ceph
  py = python3Packages;

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
    doCheck = false;  # tests require a running Consul via Docker
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
  py.buildPythonPackage rec {
    inherit version src;

    name = "fc.qemu-${version}";

    dontStrip = true;

    propagatedBuildInputs = [
      coreutils
      gptfdisk
      parted
      procps
      qemu_ceph
      systemd
      utillinux
      xfsprogs
      py.requests
      py.future
      py.colorama
      py.structlog
      py_consulate
      py.psutil
      strace
      py.pyyaml
      py.setuptools
      (py.toPythonModule ceph_client)
    ];

    passthru = {
      inherit py checkInputs;
    };

    checkInputs = [
      file
      py_pytest_patterns
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

        propagatedBuildInputs = [ py.pytest ];

        meta = with lib; {
          description = "Runs tests multiple times to expose flakiness.";
          homepage = "https://github.com/dropbox/pytest-flakefinder";
        };
      })
    ];

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      PATH="${lib.makeBinPath propagatedBuildInputs}:$PATH" pytest -vv -m "unit"
      runHook postCheck
    '';

}
