{ lib
, buildPythonPackage
, cssselect
, fetchPypi
, lxml
}:

buildPythonPackage rec {
  pname = "pyquery";
  version = "1.4.1";

  src = fetchPypi {
    inherit pname version;
    extension = "tar.gz";
    sha256 = "sha256-j893xy49YCzhCgvU5l9X8JRcGOFWJ+SRMMJxctSTnZg=";
  };

  propagatedBuildInputs = [
    cssselect
    lxml
  ];

  # circular dependency on webtest
  doCheck = false;
  pythonImportsCheck = [ "pyquery" ];

  meta = with lib; {
    description = "A jquery-like library for Python";
    homepage = "https://github.com/gawel/pyquery";
    changelog = "https://github.com/gawel/pyquery/blob/${version}/CHANGES.rst";
    license = licenses.bsd0;
  };
}
