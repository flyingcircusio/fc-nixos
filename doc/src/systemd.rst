.. _nixos2-systemd-units:

SystemD units
=============

You should register any services that you'd like to start as a systemd unit
by placing a unit file in :file:`/etc/local/systemd/<unit-name>.<type>`.

A simple unit file to start a service may look like this:

.. code-block:: ini
    :caption: myservice.service

    [Unit]
    Description=My Application Service

    [Service]
    Environment="PATH=/var/setuid-wrappers:/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:/run/current-system/sw/bin:/run/current-system/sw/sbin"

    User=s-myservice
    Group=service

    ExecStart=/srv/s-myservice/bin/runme

A few notes that you should pay attention to:

* We do not enforce the user. You can start your services as root, but that
  may easily cause permission issues and poses severe security risk. Please
  confine your services to an appropriate user, typically your service user.

* Your service should not daemonize / detach on its own. SystemD works best
  when you just start and stay attached in the foreground.

* On NixOS the environment is quite clean and you may start just using the
  :literal:`PATH` as shown above.

* We bind your units to the :literal:`multi-user.target` by default so they
  will be automatically started upon boot and stopped properly when the
  machine shuts down.

See the `systemd.service and related manpages <https://www.freedesktop.org/software/systemd/man/systemd.service.html>`_ for further information.
