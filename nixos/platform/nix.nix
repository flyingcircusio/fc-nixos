{
  config,
  lib,
  pkgs,
  ...
}:

let
  production = lib.attrByPath [ "parameters" "production" ] "" config.flyingcircus.enc;

  nixPackage = pkgs.nixVersions.nix_2_28;
in
{
  options.flyingcircus = {
    nix.useUnstableNix = lib.mkOption {
      default = production == false;
      defaultText = lib.literalExpression "production == false";
      type = lib.types.bool;
      description = ''
        This option is used to roll out newer Nix versions earlier for gradual testing.
        Right now, this has no effect.
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
