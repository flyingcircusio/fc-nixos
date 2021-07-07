{ fetchFromGitHub, lib, ceph, python3Packages }:

let
  py = python3Packages;

  telnetlib3 = py.buildPythonPackage rec {
    pname = "telnetlib3";
    version = "1.0.3";
    src = py.fetchPypi {
      inherit pname version;
      sha256 = "1jaryns15lagpdl1py2v0why3xd41ndji83fpsj1czf4kjimkdsd";
    };
    propagatedBuildInputs = [  ];
    meta = with lib; {
      description = "Python 3 asyncio Telnet server and client Protocol library
";
      homepage = http://telnetlib3.rtfd.org/;
      license = licenses.isc;
    };
  };

  murmurhash3 = py.buildPythonPackage rec {
    pname = "mmh3";
    version = "2.5.1";
    src = py.fetchPypi {
      inherit pname version;
      sha256 = "0265pvfbcsijf51szsh14qk3l3zgs0rb5rbrw11zwan52yi0jlhq";
    };
    propagatedBuildInputs = [  ];
    meta = with lib; {
      description = "a library for MurmurHash3, a set of fast and robust hash functions
";
      homepage = http://packages.python.org/mmh3;
      license = licenses.publicDomain;
    };
  };

  consulate = py.buildPythonPackage rec {
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
py.buildPythonPackage rec {
  name = "backy-${version}";
  version = "2.5.0dev";
  namePrefix = "";

  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "backy";
    rev = "80222fafe47ad4a9c3032857059c41e1b1185e03";
    sha256 = "0n0a32v657g9n03dab8zh8q47jqf66qn73f4kmapmph87ycw8j08";
  };

  buildInputs = [
    py.pytest
  ];
  propagatedBuildInputs = [
    ceph
    py.packaging
    py.structlog
    py.shortuuid
    py.python-lzo
    py.pyyaml
    py.pytz
    py.setuptools
    py.prettytable
    py.humanize
    py.tzlocal
    consulate
    murmurhash3
    telnetlib3
  ];
  dontStrip = true;
  doCheck = false;
}
