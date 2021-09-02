{ lib, fetchgit, python3Packages, smartmontools }:

with python3Packages;
buildPythonApplication{

  pname = "fc.disktracker";
  version = "1.0.0";
  src = fetchgit {
    url = "https://gitlab.flyingcircus.io/flyingcircus/fc-disktracker.git";
    rev = "713a847509764fca17232f4d9b0d633142cdeedb"; #Commit: Add ability to print given SnipeIT token and url
    sha256 = "0ydx4jqzvl2r0kz6p9ydvj8h5grsfgg6xz6dsfd6cp8zxhwyiqyf";
  };

  dontStrip = true;

  propagatedBuildInputs = [ requests smartmontools ];
}
