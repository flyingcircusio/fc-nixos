# This is just a stub to check if ffmpeg builds and to cache the result.
import ./make-test-python.nix ({ pkgs, lib, ... }:
{
  name = "ffmpeg";

  machine = {
    imports = [ ../nixos ../nixos/roles ];

    environment.systemPackages = with pkgs; [
      ffmpeg
    ];

    flyingcircus.enc.parameters.interfaces.srv = {
      mac = "52:54:00:12:34:56";
      bridged = false;
      networks = {
        "192.168.101.0/24" = [ "192.168.101.1" ];
        "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::1" ];
      };
      gateways = {};
    };

  };

  testScript = ''
    start_all()
    machine.succeed('ffmpeg -version')
  '';
})
