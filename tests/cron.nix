import ./make-test-python.nix (
  { testlib, ... }:
  {
    name = "cron";

    nodes.machine = {
      imports = [ (testlib.fcConfig { }) ];
    };

    testScript = ''
      machine.wait_for_unit("cron.service")

      # Confirm the restart policy is in place.
      machine.succeed("test \"$(systemctl show --property=Restart --value cron.service)\" = always")

      old_pid = machine.succeed(
          "systemctl show --property=MainPID --value cron.service"
      ).strip()

      # Simulate an OOM kill: SIGKILL the cron daemon without a clean shutdown.
      machine.succeed("kill -9 " + old_pid)

      # With Restart=always systemd must respawn the unit and it becomes active
      # again, with a fresh main PID.
      machine.wait_until_succeeds(
          "test \"$(systemctl show --property=MainPID --value cron.service)\" != "
          + old_pid
      )
      machine.wait_for_unit("cron.service")
      machine.succeed("systemctl is-active cron.service")
    '';
  }
)
