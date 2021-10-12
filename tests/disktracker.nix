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
    start_all()
    machine.wait_for_unit("multi-user.target")

    with subtest("Did udev script run withour error"):
        status = machine.execute('dmesg | grep -E "systemd-udevd.*disktracker.*failed"')
        if status[0] != 1:
            print(status[1])
            raise Exception

    with subtest("Disktracker service has to exists"):
        status = machine.execute('systemctl list-unit-files | grep -q "disktracker.service"')
        if status[0] != 0:
            raise Exception

    with subtest("Disktracker timer has to exists and be active"):
        status = machine.execute('systemctl list-timers | grep -qE "1min.*left.*disktracker.timer"')
        if status[0] != 0:
            raise Exception

    with subtest("Test if SnipeIT url and token are given correctly to disktracker"):
        output = machine.execute("disktracker --print-config")
        if output != (0, 'SnipeIT token is:\nTOKEN\nSnipeIT url is:\nhttps://assets.fcstag.fcio.net\n'):
            raise Exception
  '';
})
