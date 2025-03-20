{
  pkgs,
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
    src = py.fetchPypi {
      inherit pname version;
      hash = "sha256-um7KXLW6ArukyfT5ha+AxU7D3M+Uz80ZAVQ4YlXkdUM=";
    };
    propagatedBuildInputs = [ ];
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
