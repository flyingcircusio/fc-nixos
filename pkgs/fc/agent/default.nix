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
    version = "0.6";

    src = fetchFromGitHub {
      owner = "wimglenn";
      repo = "pytest-structlog";
      rev = "cb82f00cfc47696a36797a6eeb9f65ad6e727f19";
      hash = "sha256-ktLsdEtxfiWhCTTaKowBoAAijOF9640m5XV/rdahpl0=";
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
  doCheck = true;
  passthru.pythonDevEnv = python.withPackages (_: checkInputs ++ propagatedBuildInputs);

}
