# This flake is meant to be used with `nix develop`
# to provide a dev shell for platform developers and release managers.

# Platform dependencies are still read from
# release/versions.json, but the file is updated from flake inputs
# when build_versions_json is used.

# All former stand-alone scripts are now integrated into this flake.
# They can be executed from the dev shell:

# ## Dev VM
# build_channels_dir (was part of ./dev-setup)
# nixos_repl

# ## Release
# update_phps (was: up-nix-phps.sh)
# get_current_channel_url (was: fc-get-current-channel-url.sh)

{
  description = "Flying Circus NixOS platform (dev/release tooling)";

  inputs = {
    nixpkgs.url = "github:flyingcircusio/nixpkgs/nixos-26.11";
    nixos-mailserver = {
      url = "gitlab:flyingcircus/nixos-mailserver/nixos-26.05?host=gitlab.flyingcircus.io";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./release/flake-part-linux-only-packages.nix
      ];
      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          lib,
          system,
          ...
        }:
        {
          # Per-system attributes can be defined here. The self' and inputs'
          # module parameters provide easy access to attributes of the same
          # system.

          # We need our overlay here to get the right package versions.
          # Other than that, it has no effect.
          _module.args.pkgs =
            let
              inherit (builtins) elem getName;
              nixpkgsConfig = import ./nixpkgs-config.nix;
            in
            import inputs.nixpkgs {
              inherit system;
              overlays = [ (import ./pkgs/overlay.nix) ];
              config = {
                inherit (nixpkgsConfig) permittedInsecurePackages;

                allowUnfreePredicate = pkg: elem (getName pkg) nixpkgsConfig.allowedUnfreePackageNames;
              };
            };

          apps.buildVersionsJson = {
            type = "app";
            program = "${pkgs.writeShellScript "update-versions-json" ''
              jq < $(nix build .#versionsJson --print-out-paths) > release/versions.json
            ''}";
          };
          apps.buildPackageVersionsJson = {
            type = "app";
            program = "${pkgs.writeShellScript "update-package-versions-json" ''
              jq < $(nix build .#packageVersions --print-out-paths --impure) > release/package-versions.json
            ''}";
          };

          packages = {
            # These are packages that work on all systems.
            # Also see release/flake-part-linux-only-packages.nix

            fcGetCurrentChannelUrl = pkgs.writeShellApplication {
              name = "get_current_channel_url";
              runtimeInputs = with pkgs; [ curl ];
              text = (lib.readFile release/fc-get-current-channel-url.sh);
            };

            upNixPhps = pkgs.writeShellApplication {
              name = "update_phps";
              excludeShellChecks = [
                "SC2086"
                "SC2164"
                "SC2064"
                "SC2002"
              ];
              runtimeInputs = with pkgs; [
                git
                curl
                jq
              ];
              text = (lib.readFile release/up-nix-phps.sh);
            };

            versionsJson = pkgs.writeText "versions.json" (
              lib.generators.toJSON { } {
                nixpkgs = with inputs.nixpkgs; {
                  inherit rev;
                  hash = narHash;
                  owner = "flyingcircusio";
                  repo = "nixpkgs";
                };
                nixos-mailserver = with inputs.nixos-mailserver; {
                  inherit rev;
                  hash = narHash;
                  url = "https://gitlab.flyingcircus.io/flyingcircus/nixos-mailserver.git/";
                  fetchSubmodules = false;
                  deepClone = false;
                  leaveDotGit = false;
                };
                poetry2nix = with inputs.poetry2nix; {
                  inherit rev;
                  hash = narHash;
                  owner = "nix-community";
                  repo = "poetry2nix";
                };
              }
            );
          };

          devShells.default =
            let
              inherit (builtins) getEnv;
              upstreams = { inherit (inputs) nixpkgs nixos-mailserver; };
              nixPathUpstreams = lib.concatStringsSep ":" (
                lib.mapAttrsToList (name: flake: "${name}=${flake.outPath}") upstreams
              );
              NIX_PATH = "fc=${getEnv "PWD"}:${nixPathUpstreams}:nixos-config=/etc/nixos/configuration.nix";
            in
            pkgs.mkShell {
              name = "fc-nixos-dev";
              env = {
                inherit NIX_PATH;
              };

              packages =
                with pkgs;
                [
                  jq
                  nixfmt
                ]
                ++ (
                  with self'.packages;
                  [
                    fcGetCurrentChannelUrl
                    upNixPhps
                  ]
                  ++ [
                    (pkgs.writeShellApplication {
                      name = "build_channels_dir";
                      text = ''
                        set -e
                        mkdir -p channels
                        if ! [[ -e channels/fc ]]; then
                            ln -s .. channels/fc
                        fi
                      ''
                      + (lib.concatStringsSep "\n" (
                        lib.mapAttrsToList (name: flake: ''
                          nix-store --add-root channels/${name} -r ${flake.outPath}
                        '') upstreams
                      ));
                    })
                    (pkgs.writeShellApplication {
                      name = "cat_package_versions_json";
                      runtimeInputs = [ nix ];
                      text = ''
                        jq < "$(nix build .#packageVersions --print-out-paths)"
                      '';
                    })
                    (pkgs.writeShellApplication {

                      name = "dev_setup";
                      excludeShellChecks = [ "SC2154" ];
                      bashOptions = [
                        "errexit"
                        "pipefail"
                      ];
                      text = ''
                        build_channels_dir

                        # -s gives us the absolute path without resolving symlinks.
                        NIX_PATH=$(realpath -s channels)

                        # preserve nixos-config
                        config=$(nix-instantiate --find-file nixos-config 2>/dev/null) || true

                        if [[ -n "$config" ]]; then
                            NIX_PATH="$NIX_PATH:nixos-config=$config"
                        else
                            NIX_PATH="$NIX_PATH:nixos-config=$base/nixos"
                        fi

                        echo "export NIX_PATH=$NIX_PATH"
                      '';
                    })
                    (pkgs.writeShellApplication {
                      name = "nixos_repl";
                      text = ''
                        sudo -E nix repl -f nixos/lib/nixos-repl.nix
                      '';
                    })
                  ]
                );
            };
        };
    }; # end mkFlake
}
