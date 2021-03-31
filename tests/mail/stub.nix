import ../make-test-python.nix ({pkgs, lib, ...}:
{
  name = "mailstub";
  nodes = {
    mail =
      { lib, ... }: {
        imports = [ ../../nixos ../../nixos/roles ];
        config = {
          flyingcircus.roles.mailstub.enable = true;
          networking.domain = null;
        };
      };
  };
  testScript = ''
    start_all()
    # basic smoke test, should be expanded
    mail.wait_for_open_port(25)
  '';
})
