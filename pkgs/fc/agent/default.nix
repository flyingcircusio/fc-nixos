{ lib
, stdenv
, fetchFromGitHub
, dmidecode
, gitMinimal
, gptfdisk
, libyaml
, multipath-tools
, nix
, python3Packages
, util-linux
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

  pytest-structlog = py.buildPythonPackage rec {
    pname = "pytest-structlog";
    version = "0.4";

    src = fetchFromGitHub {
      owner = "wimglenn";
      repo = "pytest-structlog";
      rev = "b71518015109b292bc6584b8637264939b44af62";
      sha256 = "00g2ivgj4y398d0y60lk710zz62pj80r9ya3b4iqijkp4j8nh4gp";
    };

    buildInputs = [ py.pytest py.structlog ];
  };

in
py.buildPythonPackage rec {
  name = "fc-agent-${version}";
  version = "1.0";
  namePrefix = "";
  src = ./.;
  checkInputs = [
    py.freezegun
    py.pytest
    py.pytest-cov
    py.pytest-runner
    py.responses
    py.pytest-mock
    py.pytest-subprocess
    pytest-structlog
  ];
  propagatedBuildInputs = [
    gitMinimal
    nix
    py.click
    py.colorama
    py.python-dateutil
    py.iso8601
    py.pytz
    py.requests
    py.shortuuid
    py.structlog
    pyyaml
    util-linux
  ] ++ lib.optionals stdenv.isLinux [
    dmidecode
    gptfdisk
    multipath-tools
    py.systemd
    xfsprogs
  ];
  dontStrip = true;
}
