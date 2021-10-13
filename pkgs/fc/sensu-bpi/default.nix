{ pkgs, fetchgit, python3, python3Packages }:

let
  pysensu = python3Packages.buildPythonPackage rec{
    pname = "pysensu";
    version = "0.13.0";
    src = fetchgit {
      url = https://github.com/sangoma/pysensu.git;
      rev = "bd341dc61ec8f62b2e214168c32284829608bf25"; # Version bump to 0.13.0
      sha256 = "1xay27ka1rh5g7b6vkji39rdjz93fmhd2xsy19bngcxgpgf5yzis";
    };
    propagatedBuildInputs = with python3Packages; [wheel requests pytest];
    dontStrip = true;
  };
in
pkgs.writers.writePython3Bin "fc.sensu-bpi" { libraries = [ pysensu pkgs.python3Packages.requests ]; } ./sensu-bpi.py
