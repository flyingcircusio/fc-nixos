{ config, lib, pkgs, ... }:
{
  imports = with lib; [
    #./frontend.nix
    ./server.nix
    ./agent.nix
    (mkRenamedOptionModule [ "flyingcircus" "roles" "kubernetes-master" ] [ "flyingcircus" "roles" "k3s-server" ])
  ];

  assertions =
    let server = config.flyingcircus.roles.k3s-server.enable;
        agent = config.flyingcircus.roles.k3s-agent.enable;
    in
    [
      {
        assertion = !(server && agent);
        message = "The k3s-agent role must not be enabled together with the k3s-server role.";
      }
    ];

}
