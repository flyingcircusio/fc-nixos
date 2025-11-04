{
  pkgs,
  libyaml,
  iproute2,
  ethtool,
  python3Packages,
  megacli,
}:

let
  py = python3Packages;

in
py.buildPythonApplication rec {
  name = "fc-sensuplugins-${version}";
  version = "1.0";
  src = ./.;
  dontStrip = true;
  pyproject = true;
  build-system = [ py.setuptools ];
  propagatedBuildInputs = [
    libyaml
    iproute2
    ethtool
    megacli
    py.nagiosplugin
    py.requests
    py.requests-toolbelt
    py.psutil
    py.pyyaml
  ];
}
