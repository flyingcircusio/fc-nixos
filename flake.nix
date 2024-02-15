# This flake is meant to be used with `nix develop --impure`
# to provide a dev shell for platform developers and release managers.

# Platform dependencies are still read from
# release/versions.json, but the file is updated from flake inputs
# when update_nixpkgs / build_versions_json is used.

# All former stand-alone scripts are now integrated into this flake.
# They can be executed from the dev shell:

# ## Dev VM
# build_channels_dir (was part of ./dev-setup)
# nixos_repl

# ## Release
# update_nixpkgs (was: update-nixpkgs.py)
# update_phps (was: up-nix-phps.sh)
# show_release_branch_status (was: fc-branch-diff-release.sh)
# perform_release (was: fc-release.sh)
# get_current_channel_url (was: fc-get-current-channel-url.sh)

{
  description = "Flying Circus NixOS platform (dev/release tooling)";

  inputs = {
    nixpkgs.url = "github:flyingcircusio/nixpkgs/nixos-23.11";
    nixos-mailserver = {
      url = "gitlab:flyingcircus/nixos-mailserver?host=gitlab.flyingcircus.io";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-22_11.follows = "nixpkgs";
      inputs.nixpkgs-23_05.follows = "nixpkgs";
    };
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; }
    {
      imports = [
        inputs.devenv.flakeModule
        ./release/flake-part-linux-only-packages.nix
      ];
      systems = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
      perSystem = { config, self', inputs', pkgs, lib, system, ... }: {
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

              allowUnfreePredicate = pkg:
                elem (getName pkg) nixpkgsConfig.allowedUnfreePackageNames;
            };
          };

        packages = {
          # These are packages that work on all systems.
          # Also see release/flake-part-linux-only-packages.nix

          fcRelease = pkgs.writeShellApplication {
            name = "perform_release";
            runtimeInputs = with pkgs; [ git coreutils ];
            text = (lib.readFile release/fc-release.sh);
          };

          fcBranchDiffRelease = pkgs.writeShellApplication {
            name = "show_release_branch_status";
            runtimeInputs = with pkgs; [ gh git coreutils ];
            text = (lib.readFile release/fc-branch-diff-release.sh);
          };

          fcGetCurrentChannelUrl = pkgs.writeShellApplication {
            name = "get_current_channel_url";
            runtimeInputs = with pkgs; [ curl ];
            text = (lib.readFile release/fc-get-current-channel-url.sh);
          };

          upNixPhps = pkgs.writeShellApplication {
            name = "update_phps";
            excludeShellChecks = [ "SC2086" "SC2164" "SC2064" "SC2002" ];
            runtimeInputs = with pkgs; [ git curl jq ];
            text = (lib.readFile release/up-nix-phps.sh);
          };

          updateNixpkgs =
            pkgs.writers.writePython3Bin
              "update_nixpkgs"
              { libraries = with pkgs.python3Packages; [ GitPython rich typer ]; }
              (lib.readFile release/update-nixpkgs.py);

          versionsJson = pkgs.writeText "versions.json" (lib.generators.toJSON {}
            {
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
            }
          );
        };

        devenv.shells.default =
         let
            inherit (builtins) getEnv;
            upstreams = { inherit (inputs) nixpkgs nixos-mailserver; };
            nixPathUpstreams =
              lib.concatStringsSep ":"
                (lib.mapAttrsToList (name: flake: "${name}=${flake.outPath}") upstreams);
            NIX_PATH = "fc=${getEnv "PWD"}:${nixPathUpstreams}:nixos-config=/etc/nixos/configuration.nix";
          in
          {
            name = "fc-nixos-dev";
            env = {
              inherit NIX_PATH;
            };

            packages = with pkgs; [
              jq
            ] ++ (with self'.packages; [
              fcBranchDiffRelease
              fcGetCurrentChannelUrl
              fcRelease
              upNixPhps
              updateNixpkgs
            ]);

            scripts = {
              # This only works on Linux but I couldn't find an easy way to
              # only build this script on Linux. It just produces an error
              # message on Non-Linux because packageVersions is missing.
              build_package_versions_json.exec = ''
                jq < $(nix build .#packageVersions --print-out-paths) > release/package-versions.json
              '';

              build_versions_json.exec = ''
                jq < $(nix build .#versionsJson --print-out-paths) > release/versions.json
              '';

              build_channels_dir.exec = ''
                set -e
                mkdir -p channels
                if ! [[ -e channels/fc ]]; then
                    ln -s .. channels/fc
                fi
              '' + (lib.concatStringsSep "\n" (lib.mapAttrsToList (name: flake: ''
                ln -sfT ${flake.outPath} channels/${name}
              '') upstreams ));

              cat_package_versions_json.exec = ''
                jq < $(nix build .#packageVersions --print-out-paths)
              '';

              dev_setup.exec = ''
                build_channels_dir

                # -s gives us the absolute path without resolving symlinks.
                NIX_PATH=`realpath -s channels`

                # preserve nixos-config
                config=$(nix-instantiate --find-file nixos-config 2>/dev/null) || true

                if [[ -n "$config" ]]; then
                    NIX_PATH="$NIX_PATH:nixos-config=$config"
                else
                    NIX_PATH="$NIX_PATH:nixos-config=$base/nixos"
                fi

                echo "export NIX_PATH=$NIX_PATH"
              '';

              nixos_repl.exec = ''
                sudo -E nix repl -f nixos/lib/nixos-repl.nix
              '';
            };
          };
        };
    }; # end mkFlake
}
