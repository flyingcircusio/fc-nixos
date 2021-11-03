{ lib, fetchgit, python3Packages, smartmontools }:

with python3Packages;
buildPythonApplication rec {

  pname = "fc.disktracker";
  version = "1.0b1";
  src = fetchPypi {
    inherit pname version;
    sha256 = "0gbjqgv2ds8my9a43cpw5a1ag7m5whakqprp7wrwdmwgpwdynds9";
  };

  dontStrip = true;

  propagatedBuildInputs = [ requests smartmontools ];
}
