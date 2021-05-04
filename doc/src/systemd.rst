.. _nixos-systemd-units:


Custom SystemD units
====================

You can define your own unit files using NixOS configuration modules
in :file:`/etc/local/nixos` or plain unit files in :file:`/etc/local/systemd`.
Using NixOS configuration is the most flexible approach.
Plain unit files are more limited and may not work as expected.

A few notes that you should pay attention to:

* We do not enforce the user. You can start your services as root, but that
  may easily cause permission issues and poses severe security risk. Please
  confine your services to an appropriate user, typically your service user.

* Your service should not daemonize / detach on its own. SystemD works best
  when you just start and stay attached in the foreground.

See the `systemd.service and related manpages <https://www.freedesktop.org/software/systemd/man/systemd.service.html>`_
for further information.

NixOS Configuration
-------------------

By writing a custom NixOS module, you can define all kinds of SystemD units.

See the `NixOS options for service units <https://search.nixos.org/options?channel=20.09&from=0&size=30&sort=relevance&query=systemd.services.%3Cname%3E>`_
for all available settings.

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
        bash # adds all binaries from the bash package to PATH
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

You can still place plain unit config in in :file:`/etc/local/systemd/<unit-name>.service`
but it's deprecated on NixOS 19.03/20.09.

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
