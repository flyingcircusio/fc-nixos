.. _nixos2-external_net:

External network gateway
========================

The external network gateway (external_net) role provides connectivity between
VPN and VxLAN tunnels and the local project. Client connections across
these tunnels may access ports in the RG's backend network (srv).

Components
----------

OpenVPN
~~~~~~~

An OpenVPN gateway listens on the standard port (1194/udp) on the gateway's
frontend network (fe). The standard configuration requires two levels of
authentication: both a certificate and a valid FC login must be presented on
connection initiation. The certificate is fixed for all users of a given RG and
is mostly used to keep out dictionary attackers. This authentication scheme
requires that users connecting to the gateway have a valid login for this RG.

VxLAN
~~~~~

The external network gateway contains also provisions to interconnect the local
RG with a remote network via VxLAN_. Contact the :ref:`support` for details.

mosh
~~~~

As a courtesy, external network gateways run a mosh_ server by default.

.. _VxLAN: https://en.wikipedia.org/wiki/Virtual_Extensible_LAN
.. _mosh: https://mosh.org/


Configuration
-------------

OpenVPN
~~~~~~~

An OpenVPN server needs correct DNS settings (forward and reverse names).
Contact the :ref:`support` to get this set up. Additional options (like address
pools) can be set in :file:`/etc/local/openvpn/networks.json`. The README file
in the same directory contains a detailed description of available options.

By default, OpenVPN allocates client addresses from the pools 10.70.67.0/24 and
fd3e:65c4:fc10::/48.

.. note::

   Our OpenVPN servers push routes for the whole location (data center). This
   means that opening VPN connections to external network gateways in several
   RGs at once may not be a good idea.


VxLAN
~~~~~

A VxLAN tunnel is created if the file :file:`/etc/local/vxlan/config.json`
exists. See the accompanying README file for details.


Interaction
-----------

A default client configuration file (`*.ovpn`) is provided on OpenVPN gateways
in the directory :file:`/etc/local/openvpn`. 
Import this configuration file into your OpenVPN client of choice.
It will work with OpenVPN versions 2.4 and newer.
Older clients (please upgrade!) must set the cipher option in the config file.

Monitoring
----------

Currently, OpenVPN server processes are checked for liveness.

.. vim: set spell spelllang=en:
