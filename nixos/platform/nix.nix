{ config, lib, pkgs, ... }:

let
  production = lib.attrByPath [ "parameters" "production" ] "" config.flyingcircus.enc;

  nixPackage = if config.flyingcircus.nix.useUnstableNix
    then pkgs.nixVersions.nix_2_25
    else pkgs.nixVersions.nix_2_18;
in {
  options.flyingcircus = {
    nix.useUnstableNix = lib.mkOption {
      default = production == false;
      defaultText = lib.literalExpression ''production == false'';
      type = lib.types.bool;
      description = ''
        Whether to use a known stable Nix (i.e. 2.18) or a
        newer, potentially unstable version (i.e. 2.25).
      '';
    };

    # The option is defined in `<fc-nixos/nixos/platform/agent.nix>`.
    # This injects a function that makes sure that the agent uses the correct
    # Nix version.
    #
    # It's not feasible to modify `config.flyingcircus.agent.package` for this,
    # since downstream consumers may do that already, e.g. for slurm support.
    agent.package = lib.mkOption {
      apply = package: package.override { nix = config.nix.package; };
    };
  };

  config = {
    nix.package = nixPackage;
  };
}
