{ lib, fetchgit, python3Packages, smartmontools }:

with python3Packages;
buildPythonApplication{

  pname = "fc.disktracker";
  version = "1.0.0";
  src = fetchgit {
    url = "https://gitlab.flyingcircus.io/flyingcircus/fc-disktracker.git";
    rev = "ce905abb817945164fac6b24f44ff6dc6ba65bf7"; #Commit: Fix disktracker breaking when commandline arguments are missing
    sha256 = "0261a7nrm0499ixkdvliwx38l73aj50yln2s33jg6az5b4l9ism9";
  };

  dontStrip = true;

  propagatedBuildInputs = [ requests smartmontools ];
}
