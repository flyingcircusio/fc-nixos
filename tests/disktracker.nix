import ./make-test-python.nix ({ ... }:

{
  name = "disktracker";
  machine =
    {
      imports = [ ../nixos ];

      environment.etc."nixos/enc.json".text = ''{"parameters": {"secrets": {"snipeit/token": "TOKEN"}}}'';

      flyingcircus.services.disktracker.enable = true;
      services.telegraf.enable = false;
    };

  testScript = ''
    # Waiting long enough to ensure service stops to restart and gain failed status
    machine.sleep(5)

    with subtest("Ensure /run/disktracker file exists"):
        machine.succeed("cat /run/disktracker")

    with subtest("Disktracker service has to fail"):
        status = machine.execute('systemctl status disktracker | grep -q "status=1/FAILURE"')
        if status[0] != 0:
            raise Exception

    with subtest("Test if SnipeIT url and token are given correctly to disktracker"):
        output = machine.execute("disktracker --print-config")
        if output != (0, 'SnipeIT token is:\nTOKEN\nSnipeIT url is:\nhttps://assets.fcstag.fcio.net\n'):
            raise Exception
  '';
})
