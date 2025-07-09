{
  buildPythonApplication,
  setuptools,
  pymongo,
  python,
}:

buildPythonApplication rec {
  name = "fc-check-mongodb-${version}";
  version = "1.0";
  src = ./.;
  pyproject = true;
  build-system = [ setuptools ];
  propagatedBuildInputs = [
    pymongo
  ];

  passthru = {
    # Later we override pymongo and need the python version this is build with
    inherit python;
  };
}
