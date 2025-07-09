{
  pkgs,
  libyaml,
  python3Packages,
}:

let
  py = python3Packages;

in
py.buildPythonApplication rec {
  name = "fc-check-haproxy-${version}";
  version = "1.0";
  src = ./.;
  dontStrip = true;
  pyproject = true;
  build-system = [ py.setuptools ];
  propagatedBuildInputs = [
    py.nagiosplugin
    py.numpy
  ];
}
