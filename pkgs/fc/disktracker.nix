{ lib, fetchgit, python3Packages, smartmontools }:

with python3Packages;
buildPythonApplication rec {

  pname = "fc.disktracker";
  version = "ce905ab";
  src = fetchgit {
    url = "https://gitlab.flyingcircus.io/flyingcircus/fc-disktracker.git";
    rev = version; #Commit: Fix disktracker breaking when commandline arguments are missing
    sha256 = "0261a7nrm0499ixkdvliwx38l73aj50yln2s33jg6az5b4l9ism9";
  };

  dontStrip = true;

  propagatedBuildInputs = [ requests smartmontools ];
}
