{
  lib,
  fetchFromGitHub,
  perlPackages,
}:

perlPackages.buildPerlPackage rec {
  pname = "innotop";
  version = "1.15.0";
  src = fetchFromGitHub {
    owner = "innotop";
    repo = "innotop";
    tag = "v1.15.0";
    hash = "sha256-zzMOFvOC/QdsVnU+hWOpUgxNjojiaccL1l/bq87Shbk=";
  };

  patches = [ ./innotop.patch ];

  outputs = [ "out" ];

  # The script uses usr/bin/env perl and the Perl builder adds PERL5LIB to it.
  # This doesn't work. Looks like a bug in Nixpkgs.
  # Replacing the interpreter path before the Perl builder touches it fixes this.
  postPatch = ''
    patchShebangs .
  '';

  propagatedBuildInputs = with perlPackages; [
    DBI
    DBDmysql
    TermReadKey
  ];

  meta = {
    description = "innotop is a 'top' clone for MySQL with many features and flexibility.";
    license = lib.licenses.gpl2;
  };
}
