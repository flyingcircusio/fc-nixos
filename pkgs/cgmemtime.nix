{ stdenv
, fetchFromGitHub
}:
stdenv.mkDerivation {
  pname = "cgmemtime";
  version = "0.1";
  src = fetchFromGitHub {
    owner = "gsauthof";
    repo = "cgmemtime";
    rev = "14f7e010d3c6ce82017c6d25b060e63aeb8a7e74";
    sha256 = "08dc459zkpsw3i2sk69mrzi0mc9n8ga9zq6jwq5jckcg386h5yxw";
  };

  installPhase = ''
    mkdir -p $out/bin
    cp cgmemtime $out/bin
  '';
}
