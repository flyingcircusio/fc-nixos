{ stdenv
, fetchurl
, openssl
, coreutils
}:

stdenv.mkDerivation rec {
  name = "mailx-${version}";
  version = "12.5";

  src = fetchurl {
    url = "http://ftp.debian.org/debian/pool/main/h/heirloom-mailx/heirloom-mailx_${version}.orig.tar.gz";
    sha256 = "1b91ljly5hl7p23354anv6z8narrb8ij4p94l0vpz1imj4ha8nq1";
  };

  propagatedBuildInputs = [ openssl ];

  preBuild = ''
    makeFlagsArray=(
    MANDIR=$out/share/man1
    PREFIX=$out
    SENDMAIL=/run/wrappers/bin/sendmail
    SYSCONFDIR=$out/etc
    UCBINSTALL=${coreutils}/bin/install
    BINDIR=$out/bin
  )
  '';

  meta = {
    homepage = http://heirloom.sourceforge.net;
    description = ''
      Mailx is an intelligent mail processing system, which has
      a command syntax reminiscent of ed(1) with lines replaced by messages.
    '';
  };
}
