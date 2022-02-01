{ lib
, stdenv
, fetchPypi
, fetchFromGitHub
, dmidecode
, gitMinimal
, gptfdisk
, libyaml
, multipath-tools
, nix
, buildPythonPackage
, pythonPackages
, python
, util-linux
, xfsprogs
, pytest
, structlog
}:

let
  py = pythonPackages;

  pytest-structlog = py.buildPythonPackage rec {
    pname = "pytest-structlog";
    version = "0.4";

    src = fetchFromGitHub {
      owner = "wimglenn";
      repo = "pytest-structlog";
      rev = "b71518015109b292bc6584b8637264939b44af62";
      sha256 = "00g2ivgj4y398d0y60lk710zz62pj80r9ya3b4iqijkp4j8nh4gp";
    };

    buildInputs = [ pytest structlog ];
  };

in
buildPythonPackage rec {
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
    py.pytest
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
    py.rich
    py.shortuuid
    py.structlog
    py.typer
    py.pyyaml
    util-linux
  ] ++ lib.optionals stdenv.isLinux [
    dmidecode
    gptfdisk
    multipath-tools
    py.systemd
    xfsprogs
  ];
  dontStrip = true;
  passthru.pythonDevEnv = python.withPackages (_: checkInputs ++ propagatedBuildInputs);

}
