{ callPackage, fetchurl, ... } @ args:

callPackage ./generic.nix (args // rec {
  version = "10.2.11";

  src = fetchurl {
    url = "https://download.ceph.com/tarballs/ceph-${version}.tar.gz";
    sha256 = "1zfpj06jn9s96r1ajvnspkb1hasnwdwk7bnz5kwc8fbb7iydviwi";
  };

})
