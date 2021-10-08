import ./make-test-python.nix ({ ... }:

{
  name = "disktracker";
  machine =
    {
      imports = [ ../nixos ];

      environment.etc."nixos/enc.json".text = ''{"parameters": {"secrets": {"snipeit/token": "TOKEN"}}}'';

      flyingcircus.services.disktracker.enable = true;
      services.telegraf.enable = false;
      virtualisation.emptyDiskImages = [ 2000 2000 ];
    };

  testScript = ''
    # Waiting long enough to ensure service stops to restart and gain failed status
    start_all()

    machine.wait_for_unit("multi-user.target")

    with subtest("Did udev script run withour error"):
        status = machine.execute('dmesg | grep -E "systemd-udevd.*failed"')
        if status[0] != 1:
            raise Exception

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
