{ version, src, pkgs, python3Packages, lib, libceph, ceph-client, fetchFromGitHub, qemu_ceph, stdenv, gptfdisk, parted, xfsprogs, procps }:

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

in
  # We use buildPythonPackage instead of buildPythonApplication
  # to assist using this in a mixed buildEnv for external unit testing.
  py.buildPythonPackage rec {
    inherit version src;

    name = "fc.qemu-${version}";

    # tests are run separately in a VM test
    dontCheck = true;
    dontStrip = true;

    propagatedBuildInputs = [
      py.requests
      py.future
      py.colorama
      py.structlog
      py_consulate
      py.psutil
      py.pyyaml
      py.setuptools
      qemu_ceph
      (py.toPythonModule libceph)
      procps
      gptfdisk
      parted
      xfsprogs
      # XXX is in PATH anyways due to services.ceph.client, but specified here for
      # completeness sake. If necessary, fc.qemu needs to be parameterised via /etc/ceph/fc-ceph.conf
      ceph-client
    ];
  }
