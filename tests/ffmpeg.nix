# This is just a stub to check if ffmpeg builds and to cache the result.
import ./make-test-python.nix ({ pkgs, lib, ... }:
{
  name = "ffmpeg";

  machine = {
    imports = [ ../nixos ];

    environment.systemPackages = with pkgs; [
      ffmpeg
    ];

  };

  testScript = ''
    start_all()
    machine.succeed('ffmpeg -version')
  '';
})
