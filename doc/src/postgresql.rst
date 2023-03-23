.. _nixos-postgresql-server:

PostgreSQL
==========

Managed instance of the `PostgreSQL <http://postgresql.org>`_ database server.

Components
----------

* PostgreSQL server (9.6, 10, 11, 12, or 13)

Configuration
-------------

Managed PostgreSQL instances already have a production-grade configuration with
reasonable sized memory parameters (for example, `shared_buffers`, `work_mem`).

.. warning::

    Putting custom configuration in :file:`/etc/local/postgresql/{VERSION}/*.conf`
    doesn't work properly anymore on 21.05 and should not be used anymore.
    Some options from there will be ignored silently if they are already defined
    by our platform code. Use NixOS-based custom config as described below instead.

You can override platform and PostgreSQL defaults by using the
:code:`services.postgresql.settings` option in a custom NixOS module.
Place it in :file:`/etc/local/nixos/postgresql.nix`, for example:

.. code-block:: nix

  { config, pkgs, lib, ... }:
  {
    services.postgresql.settings = {
        log_connections = true;
        huge_pages = "try";
        max_connections = lib.mkForce 1000;
    };
  }

To override platform defaults, use :code:`lib.mkForce` before the wanted value
to give it the highest priority.

String values will automatically be enclosed in single quotes.
Single quotes will be escaped with two single quotes.
Booleans in Nix (true/false) are converted to on/off in the PostgreSQL config.

Run :command:`sudo fc-manage -b` to activate the changes (**restarts PostgreSQL!**).

See :ref:`nixos-custom-modules` for general information about writing NixOS
modules.

Interaction
-----------

Service users can use :command:`sudo -u postgres -i` to access the
PostgreSQL super user account to perform administrative commands like
:command:`createdb` and :command:`createuser`.

Service users may invoke :command:`sudo fc-manage --build`
to apply configuration changes and restart the PostgreSQL
server (if necessary).


Monitoring
----------

The default monitoring setup checks that the PostgreSQL server process is
running and that it responds to connection attempts to the standard PostgreSQL
port.


Miscellaneous
-------------

Our PostgreSQL installations have the autoexplain feature enabled by default.

.. vim: set spell spelllang=en:
