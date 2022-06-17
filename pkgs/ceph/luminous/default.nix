{ callPackage, fetchFromGitHub, fetchpatch, ... } @ args:

callPackage ./generic.nix (args // rec {
  version = "12.2.13";

  src = fetchFromGitHub {
    owner = "ceph";
    repo = "ceph";
    rev = "v${version}";
    sha256 = "sha256-VRn4rzvH/dTRSDgKhJ3Vj6xDqZoMi2/SA2aEqPlbIgw=";
  };

})
