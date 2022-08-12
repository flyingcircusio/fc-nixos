.. _nixos-firewall:

Firewall
========

On NixOS, our general firewall rules apply with a slight deviation:
access is limited by default and can be enabled on a per-case basis.

You are free to open any port you like on the frontend network (``ethfe``) which
will be accessible to the outside world. The server-to-server network is only
accessible in a limited way from the outside and freely to the machines
in the same project.

Adding custom configuration
---------------------------

To add firewall rules, you can place configuration files in
:file:`/etc/local/firewall/*`. Upon the next config activation all files placed
there will be concatenated and placed in a late stage of the firewall
configuration.

The files are shell scripts and are intended to be very simple. We check
that all lines are either:

* comments (starting with #)
* invocations of an iptables command (iptables, ip6tables, ip46tables)

After making changes to the firewall configuration, either wait for the
agent to apply it or run ``sudo fc-manage -b``.

.. note::

    Use IP addresses in firewall rules. Using host names is not reliable and
    unsupported.


Firewall chains
---------------

Use only the firewall chains mentioned below for custom rules. The built-in
chains like `INPUT` are reserved for system use.

Matching rules
^^^^^^^^^^^^^^

nixos-fw
    Standard firewall chain for subnet and port blocks.
nixos-nat-pre
    Chain for pre-routing actions like port redirects.
nixos-nat-post
    Chain for post-routing actions like masquerading.

Jump targets
^^^^^^^^^^^^

nixos-fw-accept
    Accept traffic destined to local host.

nixos-fw-refuse
    Deny traffic by replying with a ICMP unreachable message.

nixos-fw-log-refuse
    Deny traffic by replying with a ICMP unreachable message and log denied
    packets to the journal. Log rate limits apply.

nixos-fw-drop
    Throw away traffic without notifying the sender. Not recommended since this
    is hard to debug.


Examples
--------

Accept TCP traffic on ethfe to port 32542:

.. code-block:: bash

    ip46tables -A nixos-fw -p tcp -i ethfe --dport 32542 -j nixos-fw-accept

Refuse UDP traffic on ethsrv to port 2222:

.. code-block:: bash

    ip46tables -A nixos-fw -p udp -i ethsrv --dport 2222 -j nixos-fw-refuse

Refuse traffic from specific subnet (with logging):

.. code-block:: bash

    ip6tables -A nixos-fw -s 2001:db8:33::/48 -j nixos-fw-log-refuse

Masquerade outgoing traffic on ethsrv:

.. code-block:: bash

    iptables -t nat -A nixos-nat-post -o ethsrv -j MASQUERADE

Divert incoming traffic on ethfe port 22 to a different port:

.. code-block:: bash

    ip46tables -t nat -A nixos-nat-pre -i ethfe -p tcp --dport 22 -j REDIRECT --to-ports 2222


How to verify
-------------

Service users may list currently active firewall rules with :command:`sudo
iptables -L`, e.g.:

.. code-block:: bash

    iptables -L -nv    # show IPv4 firewall rules w/o DNS resolution
    ip6tables -L -nv   # show IPv6 firewall rules w/o DNS resolution

If the intended rules do not show up, check the system journal for possible
syntax errors in :file:`/etc/local/firewall` and re-run :command:`fc-manage -b`.
