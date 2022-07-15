.. _nixos-systemd-units:


Custom SystemD units
====================

You can define your own unit files using NixOS configuration modules
in :file:`/etc/local/nixos` or plain unit files in :file:`/etc/local/systemd`.
Using NixOS configuration is the most flexible and recommended approach.
Plain unit files are deprecated and may not work as expected.

A few notes that you should pay attention to:

* We do not enforce the user. You can start your services as root, but that
  may easily cause permission issues and poses severe security risks. Please
  confine your services to an appropriate user, typically your service user
  or let SystemD handle it by using `DynamicUser <http://0pointer.net/blog/dynamic-users-with-systemd.html>`_.

* Your service should not daemonize / detach on its own. SystemD works best
  when you just start and stay attached in the foreground.

See the `systemd.service and related manpages <https://www.freedesktop.org/software/systemd/man/systemd.service.html>`_
for further information.

NixOS Configuration
-------------------

By writing a custom NixOS module, you can define all kinds of SystemD units.
See the `NixOS options for service units <https://search.nixos.org/options?from=0&size=30&sort=relevance&query=systemd.services.%3Cname%3E>`_
for all available settings.

Minimal Service Example
~~~~~~~~~~~~~~~~~~~~~~~~

Place the following NixOS module in :file:`/etc/local/nixos/systemd-service-minimal-example.nix` (file name doesn't matter, just needs the .nix extension):

.. code-block:: nix

  {
    systemd.services.minimal-example = {
      description = "A minimal example for a custom systemd service";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "/srv/s-myservice/bin/runme";
        User = "s-myservice";
        Group = "service";
      };
    };
  }

This starts the service after boot and when :command:`fc-manage` is run.
It runs as user *s-myservice* and doesn't restart if the executable fails.


Application Service Example
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Place the following NixOS module in :file:`/etc/local/nixos/systemd-service-myapp.nix`:

.. code-block:: nix

  { config, pkgs, ... }:
  {
    systemd.services.myapp = {
      after = [ "network.target" "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      # When the unit changes, just do a restart with the new unit settings instead
      # of a stop/start cycle which takes longer.
      # This is safe if there's no ExecStop command.
      stopIfChanged = false;
      # Run a script before starting the actual application.
      preStart = ''
        echo "Setting up the config file...":
        echo HOST=${config.networking.hostName} > $RUNTIME_DIRECTORY/config
      '';
      path = with pkgs; [
        bash # adds all binaries from the bash package to PATH
        "/run/wrappers" # if you need something from /run/wrappers/bin, sudo, for example
      ];
      serviceConfig = {
        Description = "Run application myapp";
        # Use /run/myapp as temporary app runtime directory.
        # Can be referenced by the environment variable $RUNTIME_DIRECTORY
        RuntimeDirectory = "myapp";
        # Use /var/lib/myapp as persistent app state directory.
        # Can be referenced by the environment variable $STATE_DIRECTORY
        StateDirectory = "myapp";
        DynamicUser = true;
        # Service type simple is used by default, so the start command should not daemonize!
        ExecStart = "/srv/myapp/bin/run";
        # Set environment variables for the application.
        Environment = [
          "LD_LIBRARY_PATH=${pkgs.file}/lib"
          "VERBOSE=1"
        ];
        # Automatically restart service when it exits.
        Restart = "always";
        # Wait a second before restarting.
        RestartSec = "1s";

        # Security hardening
        CapabilityBoundingSet = "";
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        PrivateTmp = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        # Allow typical system calls for a service.
        SystemCallFilter = [
          "@system-service"
        ];
      };
      unitConfig = {
        Documentation = [
          "https://example.org/myapp"
        ];
      };
    };
  }

SystemD supports many options to harden services to limit the attack surface.
The example includes quite restrictive settings that may not work for your service.
Internet connectivity is still possible but many potentially dangerous ways to
interact with the system are prohibited.

You can check the security settings with ``systemd-analyze security myapp`` which yields
a score of 1.3 for the given config (1 is the best, 10 the worst).


Timer Example
~~~~~~~~~~~~~

Place the following NixOS module in :file:`/etc/local/nixos/systemd-mytask.nix`:

.. code-block:: nix

  { config, pkgs, ... }:
  {
    systemd.timers.mytask = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    systemd.services.mytask = {
      path = with pkgs; [
        bash # adds all executables from the bash package to PATH
        "/run/wrappers" # if you need something from /run/wrappers/bin, sudo, for example
      ];
      serviceConfig = {
        Description = "Run daily maintenance script.";
        Type = "oneshot";
        User = "test";
        ExecStart = "/srv/test/mytask.sh";
        # Set environment variables for the script.
        Environment = [
          "LD_LIBRARY_PATH=${pkgs.file}/lib"
          "VERBOSE=1"
        ];
      };
    };
  }


Plain SystemD units
-------------------

We still support plain unit config in in :file:`/etc/local/systemd/<unit-name>.service`
but it's deprecated. Use Nix config instead, as shown above.

We bind your service unit to the :literal:`multi-user.target` by default so they
will be automatically started upon boot and stopped properly when the
machine shuts down.

.. warning::

  Don't use this for services that are meant to be started by a timer!
  Oneshot services defined this way are triggered on by our management task
  which means that they will run every 10 minutes!


A simple unit file to start a service may look like this:

.. code-block:: ini
    :caption: myservice.service

    [Unit]
    Description=My Application Service

    [Service]
    Environment="PATH=/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:/run/current-system/sw/bin:/run/current-system/sw/sbin"

    User=s-myservice
    Group=service

    ExecStart=/srv/s-myservice/bin/runme
