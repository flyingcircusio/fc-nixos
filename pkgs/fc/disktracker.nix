{ lib, fetchgit, python3Packages, smartmontools }:

with python3Packages;
buildPythonApplication rec {

  pname = "fc.disktracker";
  version = "5a07742c";
  src = fetchgit {
    url = "https://gitlab.flyingcircus.io/flyingcircus/fc-disktracker.git";
    rev = version; # Commit: Give better information if smartctl failes
    sha256 = "17bdwipb62g6khzdzwj8w2zr9yawa75z2p6609kglabhqqw3nypp";
  };

  dontStrip = true;

  propagatedBuildInputs = [ requests smartmontools ];
}
