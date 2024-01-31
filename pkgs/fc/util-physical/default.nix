{
  lib, stdenv, makeWrapper
, bash, ceph-client, utillinux, systemd, coreutils, gnugrep, xfsprogs
, fc
}:


stdenv.mkDerivation rec {
  version = "0.3";
  name = "fc-util";

  src = ./.;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;

  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ bash ceph-client systemd fc.agent gnugrep utillinux coreutils xfsprogs ];

  installPhase = ''
    mkdir $out
    cd $src
    for x in *.sh; do
      name="''${x%.sh}"
      install -D -m 755 $x $out/bin/.$x
      makeWrapper $out/bin/.$x $out/bin/$name \
        --set PATH "${lib.makeBinPath propagatedBuildInputs}:$out/bin"
    done
  '';

  meta = with lib; {
    description = "Loose collection of operator scripts.";
    maintainers = [ maintainers.theuni ];
    platforms = platforms.unix;
  };

}
