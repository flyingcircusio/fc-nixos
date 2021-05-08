{ pkgs, python2Packages, lib, ceph, qemu_kvm }:

let
  py = python2Packages;


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

  py_consulate = py.buildPythonPackage rec {
    pname = "consulate";
    version = "0.6.0";
    src = py.fetchPypi {
      inherit pname version;
      sha256 = "0myp20l7ckpf8qszhkfvyzvnlai8pbrhwx30bdr8psk23vkkka3q";
    };
    propagatedBuildInputs = [
      py.requests
    ];
    meta = with lib; {
      description = "Consulate is a Python client library and set of application for the Consul service discovery and configuration system.
";
      homepage = http://packages.python.org/murmurhash3;
      license = licenses.publicDomain;
    };
  };

in
  py.buildPythonApplication rec {
    name = "fc.qemu-${version}";
    version = "1.1.5";

    src = pkgs.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "fc.qemu";
      rev = "4aa01a06d2b90ded5768a004ec283503e718d8ae";
      sha256 = "16kzjy418gqs20bah9gid3jww87m2y6yzkvsf9dnl327r3k6x406";
    };

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
      qemu_kvm
      ceph
    ];
  }
