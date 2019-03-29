{ pkgs ? import <nixpkgs> { }
, stdenv ? pkgs.stdenv
, fetchgit ? pkgs.fetchgit
}:

pkgs.buildPerlPackage rec {
  name = "innotop-1.12.0";
  src = fetchgit {
    url = "https://github.com/innotop/innotop.git";
    rev = "2fa43e316893b208ff5ce0375e5c2d62287ec4d5";
    sha256 = "0l284mmjzkadb17yrj9avyhbh5dqgdx3f5kj0yldlid28n1mx0kd";
  };

  outputs = [ "out" ];

  propagatedBuildInputs = [
    pkgs.perlPackages.DBI
    pkgs.perlPackages.DBDmysql
    pkgs.perlPackages.TermReadKey
  ];
  meta = {
    description = "innotop is a 'top' clone for MySQL with many features and flexibility.";
    license = stdenv.lib.licenses.gpl2;
  };
}
