{ buildPythonPackage
, fetchPypi
, mock
, zope_testing
, lib
}:

buildPythonPackage rec {
  pname = "zc.lockfile";
  version = "1.3.0";
  name = "${pname}-${version}";

  src = fetchPypi {
    inherit pname version;
    sha256 = "96cb13769e042988ea25d23d44cf09342ea0f887083d0f9736968f3617665853";
  };

  buildInputs = [  ];
  checkInputs = [ zope_testing mock ];

  # test discovery problems
  doCheck = false;

  meta = with lib; {
    description = "Inter-process locks";
    homepage =  https://www.python.org/pypi/zc.lockfile;
    license = licenses.zpl20;
    maintainers = with maintainers; [ goibhniu ];
  };
}
