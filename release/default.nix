# everything in release/ MUST NOT import from <nixpkgs> to get repeatable builds
{ nixpkgs ? {
  outPath = "${import ../nixpkgs.nix {}}/nixpkgs";
  revCount = 1;
  shortRev = "aaaaaaa";
}
, stableBranch ? false
, supportedSystems ? [ "x86_64-linux" ]
}:

let
  pkgs = import nixpkgs {};

in
with pkgs.lib;
with import "${nixpkgs}/pkgs/top-level/release-lib.nix" {
  inherit supportedSystems;
};

let
  version = fileContents "${nixpkgs}/.version";
  versionSuffix =
    (if stableBranch then "." else "beta") + "${toString nixpkgs.revCount}.${nixpkgs.shortRev}";

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

  versionModule =
    { system.nixos.versionSuffix = versionSuffix;
      system.nixos.revision = nixpkgs.rev or nixpkgs.shortRev;
    };

  fcSrc = cleanSource ../.;

  initialVMContents = [
    {
      source = ../nixos/etc_nixos_local.nix;
      target = "/etc/nixos/local.nix";
    }
  ];

in rec {
  fcChannel = import ./fc-channel.nix {
    inherit pkgs version;
    officialRelease = stableBranch;
    nixpkgs = fcSrc;
  };

  # Double import necessary to make this independent of <nixpkgs> used for
  # bootstrapping
  upstreamSources = import ../nixpkgs.nix { pkgs = (import nixpkgs {}); };

  channelSources =
    builtins.derivation {
      inherit fcSrc upstreamSources;
      name = "channel-sources-fc";
      system = builtins.currentSystem;
      builder = pkgs.stdenv.shell;
      PATH = with pkgs; lib.makeBinPath [ coreutils utillinux ];
      args = [ "-ec" ''
        mkdir $out
        cp -r $upstreamSources/* $out
        ln -s $fcSrc $out/fc
      ''];
      preferLocalBuild = true;
    };

  # A bootable VirtualBox virtual appliance as an OVA file (i.e. packaged OVF).
  ova = forMatchingSystems [ "x86_64-linux" ] (system:
    with pkgs;

    hydraJob ((import "${nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules =
        [ versionModule
          (import ./ova.nix {
            inherit nixpkgs channelSources;
            contents = initialVMContents;
          })
          ../nixos/platform
        ];
    }).config.system.build.virtualBoxOVA)
  );

}
