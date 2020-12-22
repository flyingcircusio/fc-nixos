.. _nixos-docker:

Docker
======

Runs a `Docker <http://docker.com>`_ daemon to use containers for application
deployment.

.. note:: Docker support is – at the moment – still experimental. Feel free to
  use it but we suggest contacting our support before putting anything into
  production.


Interaction
-----------

All service users can interact with Docker using the :command:`docker` command.

Network
-------

The Flying Circus network is already designed to allow customer application
components to talk to each other securely and reliably. Docker should be
run with the :command:`--network host` option to ensure proper integration.

If you want your container to be reachable from the public internet, make sure
it binds to an address on the :file:`ethfe` interface (or ``0.0.0.0`` or ``::``).
You then need to :ref:`open up appropriate ports in the firewall <nixos-firewall>`.

Other hosts in the same project can automatically connect to all the ports your
container provides by connecting to ``<$hostname>:<port>`` (which ends up on
on the :file:`ethsrv` interface).

All other network configurations are not supported at the moment.


.. vim: set spell spelllang=en:
