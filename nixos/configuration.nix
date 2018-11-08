{ ... }:
{
  imports = [
    ./modules/module-list.nix
  ];

  nixpkgs.overlays = [
    (import ../pkgs/overlays.nix)
  ];

  # XXX place /etc/nixos/configuration.nix inside VM
  # XXX overlay
  # XXX /root/.nix-defexpr
  # XXX /root/.nix-channels
}
