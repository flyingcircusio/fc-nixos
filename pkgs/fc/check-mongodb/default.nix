{ pkgs, python3Packages }:

python3Packages.buildPythonApplication rec {
  name = "fc-check-mongodb-${version}";
  version = "1.0";
  src = ./.;
  propagatedBuildInputs = [
    python3Packages.pymongo
  ];
}
