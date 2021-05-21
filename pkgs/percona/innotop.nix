{ lib
, fetchgit
, buildPerlPackage
, perlPackages
}:

buildPerlPackage rec {
  pname = "innotop";
  version = "1.12.0";
  src = fetchgit {
    url = "https://github.com/innotop/innotop.git";
    rev = "2fa43e316893b208ff5ce0375e5c2d62287ec4d5";
    sha256 = "0l284mmjzkadb17yrj9avyhbh5dqgdx3f5kj0yldlid28n1mx0kd";
  };

  patches = [ ./innotop.patch ];

  outputs = [ "out" ];

  # The script uses usr/bin/env perl and the Perl builder adds PERL5LIB to it.
  # This doesn't work. Looks like a bug in Nixpkgs.
  # Replacing the interpreter path before the Perl builder touches it fixes this.
  postPatch = ''
    patchShebangs .
  '';

  propagatedBuildInputs = with perlPackages; [ DBI DBDmysql TermReadKey ];

  meta = {
    description = "innotop is a 'top' clone for MySQL with many features and flexibility.";
    license = lib.licenses.gpl2;
  };
}
