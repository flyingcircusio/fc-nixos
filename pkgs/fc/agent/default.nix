{ lib
, dmidecode
, gptfdisk
, libyaml
, lvm2
, multipath_tools
, nix
, python3Packages
, utillinux
, xfsprogs
}:

let
  py = python3Packages;

  # PyYAML >= 5 has not appeared in upstream yet.
  pyyaml = py.buildPythonPackage rec {
    pname = "PyYAML";
    version = "5.1";
    src = py.fetchPypi {
      inherit pname version;
      sha256 = "15czj11s2bcgchn2jx81k0jmswf2hjxry5cq820h7hgpxiscfss3";
    };
    propagatedBuildInputs = [ libyaml ];
    meta = with lib; {
      description = "The next generation YAML parser and emitter for Python";
      homepage = https://github.com/yaml/pyyaml;
      license = licenses.mit;
    };
  };

in
py.buildPythonPackage rec {
  name = "fc-agent-${version}";
  version = "1.0";
  namePrefix = "";
  src = ./.;
  buildInputs = [
    py.freezegun
    py.pytest
    py.pytestcov
    py.pytestrunner
  ];
  propagatedBuildInputs = [
    dmidecode
    gptfdisk
    lvm2
    multipath_tools
    nix
    py.click
    py.dateutil
    py.iso8601
    py.pytz
    py.requests
    py.shortuuid
    pyyaml
    utillinux
    xfsprogs
  ];
  dontStrip = true;
}
