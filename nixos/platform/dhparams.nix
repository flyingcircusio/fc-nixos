{ lib, config, ... }:
{
  # Can be removed with fc-nixos 26.11
  config = {
    assertions = [
      {
        assertion = (config.security.dhparams.params != { }) -> config.security.dhparams.enable;
        message = "Generation of dhparams requested with 'security.dhparams.params' (params: ${lib.concatStringsSep ", " (builtins.attrNames config.security.dhparams.params)}) but 'security.dhparams.enable = false'. Set 'security.dhparams.enable = true' or remove the params. 'security.dhparams' is deprecated and will be removed in fc-nixos 26.11 in favor of ECDHE and Hybrid PQ key exchange algorithms.";
      }
    ];
  };
}
