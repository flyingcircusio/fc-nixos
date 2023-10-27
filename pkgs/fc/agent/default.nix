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
, enableSlurm ? false
}:

let
  py = pythonPackages;

  pytest-structlog = py.buildPythonPackage rec {
    pname = "pytest-structlog";
    version = "0.6-cb82f00";

    src = fetchFromGitHub {
      owner = "wimglenn";
      repo = "pytest-structlog";
      rev = "cb82f00cfc47696a36797a6eeb9f65ad6e727f19";
      hash = "sha256-ktLsdEtxfiWhCTTaKowBoAAijOF9640m5XV/rdahpl0=";
    };

    buildInputs = [ pytest structlog ];
  };

  stamina = py.buildPythonPackage rec {
    pname = "stamina";
    version = "23.1.0";
    format = "pyproject";

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-sWzj1S1liqdduBP8amZht3Cr/qkV9yzaSOMl8qeFR4Y=";
    };

    nativeBuildInputs = with py; [ hatchling hatch-vcs hatch-fancy-pypi-readme ];
    propagatedBuildInputs = with py; [ structlog tenacity typing-extensions ];
  };

in
buildPythonPackage rec {
  name = "fc-agent-${version}";
  version = "1.0";
  namePrefix = "";
  src = ./.;
  checkInputs = [
    py.freezegun
    py.pytest-cov
    py.responses
    py.pytest-mock
    py.pytest-subprocess
    pytest-structlog
  ];
  nativeCheckInputs = [
    py.pytestCheckHook
  ];
  propagatedBuildInputs = [
    gitMinimal
    nix
    py.click
    py.colorama
    py.python-dateutil
    py.iso8601
    py.pendulum
    py.pytz
    py.requests
    py.rich
    py.setuptools
    py.shortuuid
    py.structlog
    py.typer
    py.pyyaml
    stamina
    util-linux
  ] ++ lib.optionals stdenv.isLinux [
    dmidecode
    gptfdisk
    multipath-tools
    py.pystemd
    py.systemd
    xfsprogs
  ] ++ lib.optionals enableSlurm [
    py.pyslurm
  ];
  dontStrip = true;
  doCheck = true;
  passthru.pythonDevEnv = python.withPackages (_:
    checkInputs ++ [ py.pytest ] ++ propagatedBuildInputs
  );

}
