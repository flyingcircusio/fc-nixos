import ../make-test.nix ({pkgs, lib, ...}:
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
    startAll;
    # basic smoke test, should be expanded
    $mail->waitForOpenPort(25);
  '';
})
