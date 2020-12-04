.. _nixos2-redis:

Redis
=====

This role installs the `Redis <https://redis.io>`_ in-memory data structure store
in the latest version provided by NixOS.

Components
----------

* Redis

Configuration
-------------

Out of the box, Redis is set up with a couple of common default
parameters and listens on *localhost* and the IP-addresses of the
*ethsrv*-interface of your VM (See :ref:`networking` for details on this topic).

listens on the *ethsrv* interface on port 6379.

If you need to change the behaviour of Redis, you can put your
additional configuration into :file:`/etc/local/redis/custom.conf`.

Available configuration options can be found in the
`official documentation <https://redis.io/topics/config>`_.

For further information on how to activate changes on our NixOS-environment,
please consult :ref:`nixos2-local`.

The authentication password is automatically generated upon installation
and can be read *and changed* by service users. It can be found in
:file:`/etc/local/redis/password`.


Interaction
-----------

Service users may invoke :command:`sudo fc-manage --build` to apply
service configuration changes and trigger service restarts (if necessary).

Monitoring
----------

The default monitoring setup checks that the Redis server is running
and is responding to `PING <https://redis.io/commands/ping>`_.

.. vim: set spell spelllang=en:
