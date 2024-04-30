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
, buildPythonApplication
, pythonPackages
, python
, util-linux
, xfsprogs
, pytest
, structlog
}:

let
  py = pythonPackages;

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
    py.pytest
    py.pytest-cov
    py.pytest-timeout
  ];
  nativeBuildInputs = [
    py.setuptools
    py.pip
  ];
  nativeCheckInputs = [
    py.pytestCheckHook
  ];
  propagatedBuildInputs = [
    py.ipy
    py.persistent
    py.pyyaml
    py.transaction
    py.zodb
    stamina
  ];
  dontStrip = true;
  doCheck = true;
  disabledTests = [
    # Fails with: Permission denied: '/homeless-shelter
    "test_tilde_is_expanded_to_home_dir"
  ];

  passthru.pythonDevEnv = python.withPackages (_:
    checkInputs ++ [ py.pytest ] ++ propagatedBuildInputs
  );

}
