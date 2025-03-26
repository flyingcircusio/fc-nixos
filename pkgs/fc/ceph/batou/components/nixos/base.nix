{
  config,
  lib,
  pkgs,
  ...
}:
let
  fclib = config.fclib;
in
{

  flyingcircus.encServices = [
    {
      address = "host1";
      ips = [ "{{component.host1_addr.listen.host}}" ];
      location = "test";
      service = "ceph_mon-mon";
    }
  ];

  systemd.timers.logrotate.enable = lib.mkForce false;
  flyingcircus.agent.enable = lib.mkForce false;

  networking.extraHosts = ''
    {{component.host1_addr.listen.host}} host1.srv.test.gocept.net host1
  '';

  system.activationScripts.updateTransientHostname = ''
    ${pkgs.systemd}/bin/hostnamectl set-hostname --transient $(${pkgs.systemd}/bin/hostnamectl status --static)
  '';

}
