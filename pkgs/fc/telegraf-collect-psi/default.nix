{
  pkgs,
  libyaml,
  python3Packages,
  ceph,
}:

let
  py = python3Packages;

in
py.buildPythonApplication rec {
  name = "fc-telegraf-collect-psi-${version}";
  version = "1.0";
  src = ./.;
  pyproject = true;
  build-system = [ py.setuptools ];
  # dontStrip = true;
}
