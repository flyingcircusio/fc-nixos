(nixos-service-memory)=

# Service memory handling

For services we have NixOS options for memory handling.
These are calculated based on the memory of the virtual machine minus the memory overhead as defined in
[our public documentation](https://doc.flyingcircus.io/platform/infrastructure/vms/index.html#minimum-memory-requirements-nixos-based-vms-only).

The default overhead can be configured using `flyingcircus.vmMemoryOverhead`.
