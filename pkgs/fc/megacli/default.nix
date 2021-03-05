{ pkgs, python2Packages, megacli }:

let
  py = python2Packages;


  py_megacli = py.buildPythonPackage rec {
    pname = "megacli";
    version = "0.0.6";
    src = py.fetchPypi {
      inherit pname version;
      sha256 = "0n28znk63hy5q8fzc5h58y76ssr6kcb49r0zddh69rnh2k5c0g1l";
    };
    propagatedBuildInputs = [  ];
    meta = with pkgs.lib; {
      description = "Python library for MegaCli";
      homepage = https://github.com/m4ce/megacli-python;
      license = licenses.asl20;
    };
  };

  py_terminaltables = py.buildPythonPackage rec {
    pname = "terminaltables";
    version = "2.1.0";
    src = py.fetchPypi {
      inherit pname version;
      sha256 = "1x8c6l8g1s3ydbc87hgphhbxib83inal67w2ym7ly8b4g410zdik";
    };
    propagatedBuildInputs = [  ];
    meta = with pkgs.lib; {
      description = "Generate simple tables in terminals from a nested list of strings.

";
      homepage = https://github.com/Robpol86/terminaltables;
      license = licenses.mit;
    };
  };

in
  py.buildPythonApplication rec {
    name = "fc.megacli-${version}";
    version = "0.1";

    src = pkgs.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "fc.megacli";
      rev = "f6d2cc2cc5687f502d3496e2e55eeaf42d3a4431";
      sha256 = "1c32lnd47in17yj35171a3c1xr6ayrbkfr59p216dmrdz35m0vdj";
    };

    dontStrip = true;

    propagatedBuildInputs = [
      megacli py_megacli py_terminaltables
    ];
  }
