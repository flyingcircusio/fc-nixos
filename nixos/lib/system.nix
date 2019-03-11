# generic system state functions for use in all of the flyingcircus Nix stuff

{ lib, config, ... }:

let
  cfg = config.flyingcircus;

in
with lib;
{

  # Return the currently available memory. That is the minimum of the "should"
  # and the "actual" memory.
  current_memory = default:
    let
      enc_memory =
        if hasAttrByPath ["parameters" "memory"] cfg.enc
        then cfg.enc.parameters.memory
        else null;
      system_memory =
        if hasAttr "memory" cfg.system_state
        then cfg.system_state.memory
        else null;
      options = remove null [enc_memory system_memory];
    in
      if options == []
      then default
      else head (sort (options));

  current_cores = default:
      if cfg.system_state ? cores
      then cfg.system_state.cores
      else default;

}
