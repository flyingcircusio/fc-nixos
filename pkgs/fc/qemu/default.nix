{
  version,
  src,
  pkgs,
  python3Packages,
  lib,
  libceph,
  ceph_client,
  fetchFromGitHub,
  utillinux,
  coreutils,
  qemu_ceph,
  stdenv,
  gptfdisk,
  parted,
  xfsprogs,
  procps,
  systemd
}:

let
  # Python must be the same as the one used by Ceph
  py = python3Packages;

  # unreleased version
  py_consulate = py.buildPythonPackage rec {
    pname = "consulate";
    version = "1.1.0"; # unreleased version
    src = fetchFromGitHub {
      owner = "gmr";
      repo = "consulate";
      rev = "c431de9e629614b49c61c334d5f491fea3a9c5a3";
      sha256 = "1jm8l3xl274xjamsf39zgn6zz00xq5wshhvqkncnyvhqw0597cqv";
    };
    doCheck = false;  # tests require a running Consul via Docker
    propagatedBuildInputs = [
      py.requests
    ];
    meta = with lib; {
      description = "Consulate is a Python client library and set of application for the Consul service discovery and configuration system.
";
      homepage = https://pypi.org/project/consulate/;
      license = licenses.publicDomain;
    };
  };

  py_pytest_patterns = py.buildPythonPackage rec {
    pname = "pytest_patterns";
    version = "0.1.0";

    src = py.fetchPypi {
      inherit pname version;
      hash = "sha256-guKexrkDP4Ovqc87M7s8qFtW1FuVcf2PiDwh+QHcp6A=";
      format = "wheel";
      python = "py3";
    };

    format = "wheel";
    propagatedBuildInputs = [ py.pytest ];

    meta = with lib; {
      description = "pytest plugin to make testing complicated long string output easy to write and easy to debug";
      homepage = "https://pypi.org/project/pytest-patterns/";
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
      py.pyyaml
      py.setuptools
      (py.toPythonModule ceph_client)
      py_pytest_patterns
    ];

    checkInputs = [
      py.pytest
      py.pytest-cov
      py.pytest-timeout
      py.mock

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
