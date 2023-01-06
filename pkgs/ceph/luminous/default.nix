{ callPackage, fetchFromGitHub, fetchpatch, ... } @ args:

callPackage ./generic.nix (args // rec {
  version = "12.2.13";

  src = fetchFromGitHub {
    owner = "ceph";
    repo = "ceph";
    rev = "v${version}";
    sha256 = "sha256-/BDTHe4v7WlAYk/1C0bQwaPTe4L0XPHO7n1ltbBy3/0=";
    fetchSubmodules = true;
  };

})
