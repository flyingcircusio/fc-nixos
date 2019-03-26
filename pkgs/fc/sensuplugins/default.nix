{ pkgs, libyaml, python3Packages }:

let
  py = python3Packages;
  nagiosplugin = py.buildPythonPackage rec {
    name = "nagiosplugin-${version}";
    version = "1.2.4";
    src = pkgs.fetchurl {
      url = "https://pypi.python.org/packages/f0/82/4c54ab5ee763c452350d65ce9203fb33335ae5f4efbe266aaa201c9f30ad/nagiosplugin-1.2.4.tar.gz";
      sha256 = "1fzq6mhwrlz1nbcp8f7sg3rnnaghhb9nd21p0anl6dkga750l0kb";
    };
    doCheck = false;  # "cannot determine number of users (who failed)"
    dontStrip = true;
  };

in
  py.buildPythonPackage rec {
    name = "fc-sensuplugins-${version}";
    version = "1.0";
    namePrefix = "";
    src = ./.;
    dontStrip = true;
    propagatedBuildInputs = [
      libyaml
      nagiosplugin
      py.psutil
      py.pyyaml
      py.requests
    ];
  }
