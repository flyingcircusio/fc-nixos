{ callPackage, ... } @ args:

callPackage ./generic.nix (args // {
  version = "8.0.32-26";
  sha256 = "sha256-dWOQ+x9vyt14RJbcOvcKbvxj9P4OTWw4F4o7hS3ninE=";

  # includes https://github.com/Percona-Lab/libkmip.git
  fetchSubmodules = true;

  extraPatches = [
    ./abi-check.patch
  ];

  extraPostInstall = ''
    rm -r "$out"/docs
  '';
})
