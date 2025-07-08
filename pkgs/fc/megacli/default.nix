{
  pkgs,
  fetchFromGitHub,
  python3Packages,
  megacli,
}:

let
  py = python3Packages;

  py_megacli = py.buildPythonPackage rec {
    pname = "megacli";
    version = "0.0.11";
    src = py.fetchPypi {
      inherit pname version;
      hash = "sha256-cFHX3UlsplsUqKTFwcmS2q+d93O1gZ8Queatu9L1i0A=";
    };
    pyproject = true;
    build-system = [ py.setuptools ];
    propagatedBuildInputs = [ ];
    meta = with pkgs.lib; {
      description = "Python library for MegaCli";
      homepage = "https://github.com/m4ce/megacli-python";
      license = licenses.asl20;
    };
  };

  py_terminaltables = py.buildPythonPackage rec {
    pname = "terminaltables";
    version = "3.1.10";
    src = fetchFromGitHub {
      owner = "matthewdeanmartin";
      repo = "terminaltables3";
      rev = "v${version}";
      hash = "sha256-bnnOiO26e3Bidrls82P/vc+DNAwKSpXhjClCdfXMoFE=";
    };

    prePatch = ''
      substituteInPlace pyproject.toml \
        --replace-fail "poetry>=0.12" "poetry-core" \
        --replace-fail "build-backend = \"poetry.masonry.api\"" "build-backend = \"poetry.core.masonry.api\""
    '';

    pyproject = true;

    build-system = [ py.poetry-core ];

    meta = with pkgs.lib; {
      description = "Generate simple tables in terminals from a nested list of strings.";
      homepage = "https://github.com/Robpol86/terminaltables";
      license = licenses.mit;
    };
  };

in
py.buildPythonApplication rec {
  name = "fc.megacli-${version}";
  version = "0.1";

  pyproject = true;

  src = pkgs.fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "fc.megacli";
    rev = "bde8406d6b992c6d4fa24d5caddfcd7ec830ba13";
    hash = "sha256-LzC4vl70FlXqXn44w5HI7kd14RQ7YV6W6phPJSDJ75E=";
  };

  build-system = [
    py.hatchling
  ];

  dontStrip = true;

  propagatedBuildInputs = [
    megacli
    py_megacli
    py_terminaltables
  ];
}
