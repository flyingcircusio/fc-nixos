# generic system state functions for use in all of the flyingcircus Nix stuff

{ lib, config, ... }:

let
  cfg = config.flyingcircus;

in
with lib;
rec {

  # Return the currently available memory. That is the minimum of the "should"
  # and the "actual" memory.
  currentMemory =
    default:
    let
      enc_memory =
        if hasAttrByPath [ "parameters" "memory" ] cfg.enc then cfg.enc.parameters.memory else null;
      system_memory = if hasAttr "memory" cfg.systemState then cfg.systemState.memory else null;
      options = remove null [
        enc_memory
        system_memory
      ];
    in
    if options == [ ] then default else head (sort lessThan options);

  # Returns the
  # This method is discouraged, as it leads to issues after reboot when the kernel
  # allocates memory for internal structures slightly differently.
  # Additionally it also changes *directly* when the memory in the directory goes down.
  # Not all services however support specifying memory in ExecStartPre. In the future
  # we may support scenarios like this with explicit configs on memory changes
  # PL-135498
  currentAvailableMemory = default: (currentMemory default) - cfg.vmMemoryOverhead;

  currentCores = default: if cfg.systemState ? cores then cfg.systemState.cores else default;

}
