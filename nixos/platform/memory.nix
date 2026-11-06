{ config, lib, ... }: {
  options = {
    flyingcircus.vmMemoryOverhead = lib.mkOption {
      default = 2304;
      type = lib.types.int;
      description = ''
        Memory overhead of the VM used for the system and operating system components.

        This is used to calculate memory for services to use.

        This is equivalent to https://doc.flyingcircus.io/platform/infrastructure/vms/index.html#minimum-memory-requirements-nixos-based-vms-only
        without the kernel structures as these are already subtracted from the memory available to the OS.
      '';
    };
  };
}
