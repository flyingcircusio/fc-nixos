{ config, lib, pkgs, ... }:
{
  imports = with lib; [
    #./frontend.nix
    ./server.nix
    ./agent.nix
    (mkRenamedOptionModule [ "flyingcircus" "roles" "kubernetes-master" ] [ "flyingcircus" "roles" "k3s-server" ])
  ];

}
