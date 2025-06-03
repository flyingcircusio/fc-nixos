{ buildPythonApplication, pymongo }:

buildPythonApplication rec {
  name = "fc-check-mongodb-${version}";
  version = "1.0";
  src = ./.;
  propagatedBuildInputs = [
    pymongo
  ];
}
