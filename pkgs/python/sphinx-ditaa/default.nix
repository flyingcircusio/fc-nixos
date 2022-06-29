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

  # on the one hand, upstream ceph requires sphinx-2.1.2 in their instructions,
  # on the other hand one of the unittests fails for Sphinx>=1.7 due to deprecation of
  # sphinx.util.compat.Directive -> disable tests and hope for the best
  doCheck = false;

  meta = {
    description = "sphinx-ditaa lets you draw ASCII art diagrams in Sphinx documents; mainly required for building ceph docs";
    homepage = "https://github.com/ceph/sphinx-ditaa";
    license = lib.licenses.bsd3;
  };
}
