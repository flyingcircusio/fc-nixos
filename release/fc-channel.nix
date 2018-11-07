{ pkgs
, nixpkgs
, version
, officialRelease ? false
}:

pkgs.releaseTools.sourceTarball {
  name = "fc-channel";
  src = nixpkgs;
  buildInputs = [ pkgs.nix ];

  inherit version officialRelease;

  distPhase = ''
    rm -rf .git
    releaseName="fc-$VERSION$VERSION_SUFFIX"
    mkdir -p $out/tarballs
    cp -prd . ../$releaseName
    chmod -R u+w ../$releaseName
    cd ..
    tar cfJ $out/tarballs/''${releaseName}.tar.xz $releaseName
  '';
}
