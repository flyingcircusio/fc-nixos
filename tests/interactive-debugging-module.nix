{ lib, config, ... }:
{
  options = {
    testdebug.sshport = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "When running the test interactively, an openssh server with an open root login is forwarded to the specified port on the test runner host.";
    };
  };
config = {
  security.pam.services.sshd.allowNullPassword = true;
  services.openssh = {
    enable = builtins.trace "enabling interactive root SSH login on ${toString config.testdebug.sshport}" true;
    settings = {
      PermitRootLogin = "yes";
      PermitEmptyPasswords = "yes";
    };
  };
  virtualisation.forwardPorts = [
    { from = "host"; host.port = config.testdebug.sshport; guest.port = 22; }
  ];
};
}
