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
  pytest-structlog = pyPackages.buildPythonPackage (finalAttrs: {
    pname = "pytest-structlog";
    version = "1.2";
    pyproject = true;
    build-system = with pyPackages; [
      setuptools
    ];

    src = fetchFromGitHub {
      owner = "wimglenn";
      repo = "pytest-structlog";
      rev = "v${finalAttrs.version}";
      hash = "sha256-4QzqlJStAF83lGgtfRB5cKGybmatWMQo0g9l0PZzfGw=";
    };

    dependencies = with pyPackages; [
      pytest
      structlog
    ];
  });

  stamina = pyPackages.buildPythonPackage rec {
    pname = "stamina";
    version = "23.1.0";
    format = "pyproject";

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-sWzj1S1liqdduBP8amZht3Cr/qkV9yzaSOMl8qeFR4Y=";
    };

    build-system = with pyPackages; [
      hatchling
      hatch-vcs
      hatch-fancy-pypi-readme
    ];
    dependencies = with pyPackages; [
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
