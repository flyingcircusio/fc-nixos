{ buildPythonPackage
, lib
, fetchFromGitHub
, ditaa
, sphinx
}:

let
  pname = "sphinx-ditaa";
  version = "0.0.1";
in
buildPythonPackage {
  inherit pname version;
  #name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "ceph";
    repo = pname;
    # latest master commit from 2017, there are no releases
    rev = "81d423c365cd9da9b815a45b1cde05b118c472f4";
    sha256 = "sha256-mpB+xvPfDmWj3vt2uo7CuI4eNgkxdGrZBECKfA1VHYk=";
  };

  propagatedBuildInputs = [ ditaa sphinx ];

  meta = {
    description = "sphinx-ditaa lets you draw ASCII art diagrams in Sphinx documents; mainly required for building ceph docs";
    homepage = "https://github.com/ceph/sphinx-ditaa";
    license = lib.licenses.bsd3;
  };
}
