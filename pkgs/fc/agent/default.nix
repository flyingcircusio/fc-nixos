{
  lib,
  stdenv,
  fetchPypi,
  fetchFromGitHub,
  dmidecode,
  gitMinimal,
  gptfdisk,
  libyaml,
  multipath-tools,
  nix,
  pyPackages,
  python,
  util-linux,
  xfsprogs,
  enableSlurm ? false,
}:

let
  pytest-structlog = pyPackages.buildPythonPackage rec {
    pname = "pytest-structlog";
    version = "0.6-cb82f00";
    pyproject = true;
    build-system = with pyPackages; [
      setuptools
    ];

    src = fetchFromGitHub {
      owner = "wimglenn";
      repo = "pytest-structlog";
      rev = "cb82f00cfc47696a36797a6eeb9f65ad6e727f19";
      hash = "sha256-ktLsdEtxfiWhCTTaKowBoAAijOF9640m5XV/rdahpl0=";
    };

    buildInputs = with pyPackages; [
      pytest
      structlog
    ];
  };

  stamina = pyPackages.buildPythonPackage rec {
    pname = "stamina";
    version = "25.1.0";
    format = "pyproject";

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-rWdICXlq5AUSs7YpbPregm79Y4Y/8sovWfgGNC6R6Uo=";
    };

    nativeBuildInputs = with pyPackages; [
      hatchling
      hatch-vcs
      hatch-fancy-pypi-readme
    ];
    propagatedBuildInputs = with pyPackages; [
      structlog
      tenacity
      typing-extensions
    ];
  };

in
pyPackages.buildPythonPackage rec {
  name = "fc-agent-${version}";
  version = "1.0";
  format = "pyproject";
  namePrefix = "";
  src = ./.;
  checkInputs = [
    pyPackages.freezegun
    pyPackages.pytest-cov
    pyPackages.responses
    pyPackages.pytest-mock
    pyPackages.pytest-subprocess
    pytest-structlog
  ];
  nativeCheckInputs = [
    pyPackages.pytestCheckHook
  ];
  propagatedBuildInputs = [
    gitMinimal
    nix
    pyPackages.click
    pyPackages.colorama
    pyPackages.configobj
    pyPackages.python-dateutil
    pyPackages.iso8601
    pyPackages.netaddr
    pyPackages.pendulum
    pyPackages.requests
    pyPackages.rich
    pyPackages.setuptools
    pyPackages.shortuuid
    pyPackages.structlog
    pyPackages.typer
    pyPackages.pyyaml
    stamina
    util-linux
  ]
  ++ lib.optionals stdenv.isLinux [
    dmidecode
    gptfdisk
    multipath-tools
    pyPackages.pystemd
    pyPackages.systemd-python
    xfsprogs
  ]
  ++ lib.optionals enableSlurm [
    pyPackages.pyslurm
  ];
  dontStrip = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck

    pytest -vv

    runHook postCheck
  '';
  passthru.pythonDevEnv = python.withPackages (
    _: checkInputs ++ [ pyPackages.pytest ] ++ propagatedBuildInputs
  );

  outputs = [
    "out"
    "qa"
  ];

  postCheck = ''
    cp -a htmlcov/ $qa/
  '';

}
