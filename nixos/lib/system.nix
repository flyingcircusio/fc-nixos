# generic system state functions for use in all of the flyingcircus Nix stuff

{ lib, config, ... }:

let
  cfg = config.flyingcircus;

in
with lib;
{

  # Return the currently available memory. That is the minimum of the "should"
  # and the "actual" memory.
  currentMemory = default:
    let
      enc_memory =
        if hasAttrByPath ["parameters" "memory"] cfg.enc
        then cfg.enc.parameters.memory
        else null;
      system_memory =
        if hasAttr "memory" cfg.systemState
        then cfg.systemState.memory
        else null;
      options = remove null [enc_memory system_memory];
    in
      if options == []
      then default
      else head (sort lessThan options);

  currentCores = default:
      if cfg.systemState ? cores
      then cfg.systemState.cores
      else default;

}
