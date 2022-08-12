.. _nixos-memcached:

Memcached
=========

This role installs the `Memcached <https://memcached.org>`_ memory object caching
system in the latest version provided by NixOS.

Configuration
-------------

Out of the box, Memcached is set up with a couple of common default
parameters and listens on *localhost* and the IP-addresses of the
*ethsrv*-interface of your VM (See :ref:`networking` for details on this topic).

If you need to change the behaviour of Memcached, you have to put the
changed options into a JSON file and save it
to :file:`/etc/local/memcached/memcached.json`.

For further information on how to activate changes on our NixOS-environment,
please consult section :ref:`nixos-local`.

Supported options are:

- **port**: The port memcached should listen on. Default: 11211
- **maxMemory**: The maximum amount of memory to use for storage in MB.
  Default: 64
- **maxConnections**: The maximum amount of simultaneous connections. Default: 1024
- **extraOptions**: A string containing any additional command line options you
  like Memcached to be started with. For reference consult Memcached's man page.

So a basic non-default configuration might look like::

    {
      "port": "11211",
      "maxMemory": "256",
      "maxConnections": "2048"
    }
