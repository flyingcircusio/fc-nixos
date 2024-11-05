{ python3Packages }:
python3Packages.buildPythonPackage rec {
  pname = "pytest_patterns";
  version = "0.3.0";

  src = python3Packages.fetchPypi {
    inherit pname version;
    hash = "sha256-OZlzoyWlYfb28mFJ8PBz4KApOZNeOtPxaLQn/pINLz0=";
    format = "wheel";
    python = "py3";
  };

  format = "wheel";
  propagatedBuildInputs = [ python3Packages.pytest ];

  meta = {
    description = "pytest plugin to make testing complicated long string output easy to write and easy to debug";
    homepage = "https://pypi.org/project/pytest-patterns/";
  };
}
