{ stdenv, lib, fetchFromGitHub,
  libcap, openssl, libsodium, zlib, libxcrypt, perl,
  withSftp ? true
}:
stdenv.mkDerivation (finalAttrs: {
    name = "proftpd-${finalAttrs.version}";
    # customer deployments already use the RC, let's wait with nixpkgs
    # upstreaming until 1.3.9 is released
    version = "1.3.9rc2";

    # as long as the release tarballs are not reproducable, better build from repo
    src = fetchFromGitHub {
      owner = "proftpd";
      repo = "proftpd";
      rev = "v${finalAttrs.version}";
      hash = "sha256-MkIZzYJuu8BLT4GFFgYOa/h/XayYxBfRbaEkvkSto+c=";
    };

    buildInputs = [
      libcap
      libsodium
      openssl
      zlib
      perl
     ];

    patches = [ ./no-adjust-ownership.patch ];

    configureFlags =
      lib.optional (!isNull openssl) "--enable-openssl" ++
      lib.optional withSftp "--with-modules=mod_sftp"
    ;
    # TODO for upstreaming: way to provide a customisable list of modules to
    # enable, there are far more than mod_sftp.
    # `$ ./configure --with-modules=mod_readme:mod_ldap`

    enableParallelBuilding = true;
    meta = {
      homepage = http://www.proftpd.org/;
      description = "Highly configurable GPL-licensed FTP server software";
      maintainers = lib.teams.flyingcircus.members;
    };
})
