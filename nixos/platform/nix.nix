{
  config,
  lib,
  pkgs,
  ...
}:

let
  production = lib.attrByPath [ "parameters" "production" ] "" config.flyingcircus.enc;

  nixPackage = pkgs.nixVersions.nix_2_34;
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

    # Nix 2.34 switches from the `tarball-cache` directory to the
    # `tarball-cache-v2` directory without cleaning up the first one.
    # This could lead to disk space issues. So we clean it up.
    # The directory could be in each users home directory while most likely
    # it primarily exists in /root/, because the fc-agent runs there.
    systemd.services."fc-cleanup-nix-tarball-cache-v1" =
      let
        tarballCacheDirectories = lib.unique (
          lib.mapAttrsToList (_: cfg: "${cfg.home}/.cache/nix/tarball-cache") config.users.users
        );
      in
      lib.mkIf (lib.versionAtLeast config.nix.package.version "2.34") {
        wantedBy = [ "multi-user.target" ];
        unitConfig = {
          # The | makes this condition OR based. When one directory exists,
          # this systemd service runs.
          ConditionPathExists = lib.map (v: "|${v}") tarballCacheDirectories;
        };
        serviceConfig = {
          User = "root";
        };
        script = builtins.concatStringsSep "\n" (lib.map (v: "rm -rf ${v}") tarballCacheDirectories);
      };
  };
}
