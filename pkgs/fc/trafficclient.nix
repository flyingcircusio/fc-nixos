{
  fetchPypi,
  fetchFromGitHub,
  buildPythonPackage,
  buildPythonApplication,
  python,
  pytest,
  pytest-cov,
  pytest-timeout,
  hatchling,
  hatch-vcs,
  hatch-fancy-pypi-readme,
  structlog,
  tenacity,
  typing-extensions,
  setuptools,
  pip,
  ipy,
  persistent,
  pyyaml,
  transaction,
  zodb,
  pytestCheckHook,
}:

let

  stamina = buildPythonPackage rec {
    pname = "stamina";
    version = "23.1.0";
    format = "pyproject";

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-sWzj1S1liqdduBP8amZht3Cr/qkV9yzaSOMl8qeFR4Y=";
    };

    nativeBuildInputs = [
      hatchling
      hatch-vcs
      hatch-fancy-pypi-readme
    ];
    propagatedBuildInputs = [
      structlog
      tenacity
      typing-extensions
    ];
  };
in
buildPythonApplication rec {
  name = "fc-trafficclient-${version}";
  version = "1.0";
  namePrefix = "";

  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "trafficclient";
    rev = "68d5ae84ebcbb4787de92a6de917da7284f80f4b";
    hash = "sha256-dp91sPzcoq4QF/odkWZ96a3y4ZctQoWQjgcVmaDcw5M=";
  };

  checkInputs = [
    pytest
    pytest-cov
    pytest-timeout
  ];
  nativeBuildInputs = [
    setuptools
    pip
  ];
  nativeCheckInputs = [
    pytestCheckHook
  ];
  propagatedBuildInputs = [
    ipy
    persistent
    pyyaml
    transaction
    zodb
    stamina
  ];
  dontStrip = true;
  doCheck = true;
  disabledTests = [
    # Fails with: Permission denied: '/homeless-shelter
    "test_tilde_is_expanded_to_home_dir"
  ];

  passthru.pythonDevEnv = python.withPackages (_: checkInputs ++ [ pytest ] ++ propagatedBuildInputs);

}
