# everything in release/ MUST NOT import from <nixpkgs> to get repeatable builds
{ nixpkgs ? {
  outPath = (import ../nixpkgs.nix {});
  revCount = 130979;
  shortRev = "gfedcba";
}
, stableBranch ? false
, supportedSystems ? [ "x86_64-linux" ]
}:

with import "${nixpkgs}/pkgs/top-level/release-lib.nix" { inherit supportedSystems; };
with import "${nixpkgs}/lib";

let

  version = fileContents "${nixpkgs}/.version";
  versionSuffix =
    (if stableBranch then "." else "beta") + "${toString (nixpkgs.revCount - 151577)}.${nixpkgs.shortRev}";

  importTest = fn: args: system: import fn ({
    inherit system;
  } // args);

  # test support
  callTestOnMatchingSystems = systems: fn: args:
    forMatchingSystems
      (intersectLists supportedSystems systems)
      (system: hydraJob (importTest fn args system));
  callTest = callTestOnMatchingSystems supportedSystems;

  callSubTests = callSubTestsOnMatchingSystems supportedSystems;
  callSubTestsOnMatchingSystems = systems: fn: args: let
    discover = attrs: let
      subTests = filterAttrs (const (hasAttr "test")) attrs;
    in mapAttrs (const (t: hydraJob t.test)) subTests;

    discoverForSystem = system: mapAttrs (_: test: {
      ${system} = test;
    }) (discover (importTest fn args system));

  in foldAttrs mergeAttrs {} (map discoverForSystem (intersectLists systems supportedSystems));

  pkgs = import nixpkgs {};

  versionModule =
    { system.nixos.versionSuffix = versionSuffix;
      system.nixos.revision = nixpkgs.rev or nixpkgs.shortRev;
    };

  cleanedFcNixOS = lib.cleanSource ../.;

  arrangeChannels =
    builtins.toFile "arrange-channels.sh" ''
      mkdir $out
      ln -s $nixpkgs $out/nixos
      ln -s $cleanedFcNixOS $out/fc
    '';

in rec {

  nixosChannel = import "${nixpkgs}/nixos/lib/make-channel.nix" {
    inherit pkgs nixpkgs version versionSuffix;
  };

  fcChannel = import ./fc-channel.nix {
    inherit pkgs version;
    officialRelease = stableBranch;
    nixpkgs = cleanedFcNixOS;
  };

  channelSources =
    builtins.derivation {
      inherit nixpkgs cleanedFcNixOS;

      name = "channel-sources";
      system = builtins.currentSystem;
      builder = pkgs.stdenv.shell;
      PATH = with pkgs; lib.makeBinPath [ coreutils utillinux ];
      args = [ "-e" arrangeChannels ];
      preferLocalBuild = true;
    };

  # A bootable VirtualBox virtual appliance as an OVA file (i.e. packaged OVF).
  ova = forMatchingSystems [ "x86_64-linux" ] (system:
    with pkgs;

    hydraJob ((import "${nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules =
        [ versionModule
          (import ./ova.nix { inherit nixpkgs channelSources; })
        ];
    }).config.system.build.virtualBoxOVA)
  );

}
