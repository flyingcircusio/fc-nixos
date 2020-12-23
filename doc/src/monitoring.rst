.. _nixos-monitoring:

Monitoring
==========

NixOS machines are monitored by `Sensu Core <https://sensu.io>`_ (1.x) with various plugins.
We run checks regularly by default to ensure platform and service health.
Check results are displayed on the status pages at `My Flying Circus <https://my.flyingcircus.io>`_.
Refer to the role documentation pages for information about what is checked for a specific role.


Custom Checks
-------------

Configure custom checks in :file:`/etc/sensu-client`.
This directory is passed to sensu as additional config directory.
You can add .json files for your checks there.
Refer to the `Sensu check guide <https://docs.sensu.io/sensu-core/1.0/guides/intro-to-checks/>`_
for more information and available options.

Example:

.. code-block:: json

    {
        "checks" : {
            "my-custom-check" : {
            "notification" : "custom check broken",
            "command" : "/srv/user/bin/nagios_compatible_check",
            "interval": 60,
            "standalone" : true
            },
            "my-other-custom-check" : {
            "notification" : "custom check broken",
            "command" : "/srv/user/bin/nagios_compatible_other_check",
            "interval": 600,
            "standalone" : true
            }
        }
    }

To activate the checks, run :command:`sudo fc-manage --build`.
For further information about local configuration, also see :ref:`nixos-local`.

The following packages are available in the sensu check PATH:

* bash
* coreutils
* glibc
* lm_sensors
* `monitoring-plugins <https://www.monitoring-plugins.org/doc/index.html>`_
* nix
* openssl
* procps
* sensu
* sysstat

You can use :code:`sudo -iu <s-user> <command>` to run commands in a service user context.
