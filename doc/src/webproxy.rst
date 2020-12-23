.. _nixos-webproxy:

Varnish (Webproxy)
==================

This role provides Varnish.


How we differ from what you are used to
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Here is how we differ from what you already know from common Linux distributions
and how you are used to configure, start, stop and maintain these packages.

* **configuration file locations:**

  Since we use NixOS, configuration files have to be edited in
  :file:`/etc/local/varnish`, followed by a NixOS rebuild which copies them into
  the Nix store and activates the new configuration. To do so, run the command
  :command:`sudo fc-manage --build`.


* **service control:**

  We use :command:`systemd` to control processes. You can use familiar commands
  like :command:`sudo systemctl restart varnish` to control services.
  However, remember that invoking :command:`sudo fc-manage --build` is
  necessary to put configuration changes into effect. A simple restart is not
  sufficient. For further information, also see :ref:`nixos-local`.

Role configuration
------------------

Your custom configuration goes to
:file:`/etc/local/varnish/default.vcl`. Please note that all
configuration has to be performed as a service user.


Monitoring
----------

* We monitor that the varnishd process is running.
* Please add a custom http checks which suite your needs to to :file:`/etc/local/sensu-client`, for instance::

    {
      "varnish": {
        "command": "check_http -H localhost -p 8080",
        "notification" : "varnish broken",
        "interval": 120,
        "standalone": true
      }
    }
