{ lib, buildPythonPackage, fetchPypi
, cheroot, contextlib2, portend, routes, six
, setuptools_scm, zc_lockfile
, backports_unittest-mock, objgraph, pathpy, pytest, pytestcov
, backports_functools_lru_cache, requests_toolbelt
}:

buildPythonPackage rec {
  pname = "CherryPy";
  version = "17.4.2";

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-7xYZrRYfUmdF1PDk5Rd1PZ2YWBTxKA4zBmEzPSugXN8=";
  };

  propagatedBuildInputs = [ cheroot contextlib2 portend routes six zc_lockfile ];

  buildInputs = [ setuptools_scm ];

  checkInputs = [ backports_unittest-mock objgraph pathpy pytest pytestcov backports_functools_lru_cache requests_toolbelt ];
  # import problems of zc.lockfile
  doCheck = false;

  checkPhase = ''
    LANG=en_US.UTF-8 pytest
  '';

  meta = with lib; {
    homepage = "http://www.cherrypy.org";
    description = "A pythonic, object-oriented HTTP framework";
    license = licenses.bsd3;
  };
}
