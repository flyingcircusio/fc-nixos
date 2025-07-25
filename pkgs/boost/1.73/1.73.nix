{
  callPackage,
  fetchurl,
  fetchpatch,
  ...
}@args:

callPackage ./generic.nix (
  args
  // rec {
    version = "1.73.0";

    src = fetchurl {
      urls = [
        "mirror://sourceforge/boost/boost_${builtins.replaceStrings [ "." ] [ "_" ] version}.tar.bz2"
        "https://boostorg.jfrog.io/artifactory/main/release/${version}/source/boost_${
          builtins.replaceStrings [ "." ] [ "_" ] version
        }.tar.bz2"
      ];
      # SHA256 from http://www.boost.org/users/history/version_1_73_0.html
      sha256 = "4eb3b8d442b426dc35346235c8733b5ae35ba431690e38c6a8263dce9fcbb402";
    };

    patches = [
      # python-3.10 compatibility, see https://github.com/ceph/ceph/pull/47027
      (fetchpatch {
        url = "https://github.com/boostorg/python/commit/d9f06052e28873037db7f98629bce72182a42410.diff?full_index=1";
        hash = "sha256-L4GR93WwzF3ZTl30zr4mGTYUbtxoUrvDe6UO0Dovncg=";
        extraPrefix = "libs/python/";
        stripLen = 1;
      })
    ];
  }
)
