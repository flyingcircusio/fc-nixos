.. _nixos2-postgresql-server:

PostgreSQL
==========

Managed instance of the `PostgreSQL <http://postgresql.org>`_ database server.

Components
----------

* PostgreSQL server (9.6, 10, 11, or 12)

Configuration
-------------

Managed PostgreSQL instances already have a production-grade configuration with
reasonable sized memory parameters (for example, `shared_buffers`, `work_mem`).

Project-specific configuration can be placed in into :file:`/etc/local/postgresql/{VERSION
}/*.conf`.


Interaction
-----------

Service users can use :command:`sudo -u postgres -i` to access the
PostgreSQL super user account to perform administrative commands like
:command:`createdb` and :command:`createuser`.

Both service users and the `postgres` DB super user may invoke :command:`sudo
fc-manage --build` to apply configuration changes and restart the PostgreSQL
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
