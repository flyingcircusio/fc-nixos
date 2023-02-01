{ version, src, pkgs, python3Packages, lib, libceph, ceph-client, fetchFromGitHub, qemu_ceph, stdenv, gptfdisk, parted, xfsprogs, procps, py_consulate }:

let
  # Python must be the same as the one used by Ceph
  py = python3Packages;

  # FIXME: try upgrading to 21.1.0 shipped with nixpkgs-21.05
  py_structlog = py.buildPythonPackage rec {
    pname = "structlog";
    version = "16.1.0";
    src = py.fetchPypi {
      inherit pname version;
      sha256 = "00dywyg3bqlkrmbrfrql21hpjjjkc4zjd6xxjyxyd15brfnzlkdl";
    };
    propagatedBuildInputs = [ py.six ];
    doCheck = false;
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
      py_structlog
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
