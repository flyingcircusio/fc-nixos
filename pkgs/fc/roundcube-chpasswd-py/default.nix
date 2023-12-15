{ pkgs, python3Packages }:

python3Packages.buildPythonApplication rec {
  name = "fc-roundcube-chpasswd-${version}";
  version = "1.0";
  src = ./.;
  propagatedBuildInputs = [
    pkgs.mkpasswd
    pkgs.apacheHttpd # for htpasswd
  ];
}
