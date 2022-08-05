.. _nixos-local:

Local Configuration
===================

You can customize the system's configuration for managed components with
config files that are located in :file:`/etc/local/*`.

Every component that supports customizing its configuration creates a directory
writable by service users, such as :file:`/etc/local/firewall`.
The specific format and allowed filenames depend on the specifics of each
component and are documented separately.

Changes to the files in the local configuration directory are picked up
automatically upon the next run of our configuration agent (generally every
10 minutes) but you can also explicitly trigger it by running:

.. code-block:: console

  $ sudo fc-manage --build

This will update the machine's system configuration, which includes copying the
local configuration files into the Nix store. Your custom config is thus
versioned along the general system config (in case we have to revert to an
older configuration version) and is atomically loaded and activated.

To inspect the result of this call, you can check the journal:

.. code-block:: console

  $ journalctl --since -1h --unit fc-manage

fc-manage
---------

:command:`fc-manage` is our utility that updates a system's configuration and
calls the underlying NixOS commands.

The basic call to apply changed configuration is:

.. code-block:: console

  $ sudo fc-manage --build
  # Short form
  $ sudo fc-manage -b

This will pick up locally changed configuration but will not perform general OS
updates or fetch new data from our configuration management database (like
adding new users or IPs).

The call to perform extensive updates including potential OS updates (the
"channel") and changes from the configuration management database (CMDB,
directory, "ENC") is:

.. code-block:: console

  $ sudo fc-manage --directory --channel
  # Short form:
  $ sudo fc-manage -ec

A mixed form (no OS updates but include changes from the CMDB) is:

.. code-block:: console

  $ sudo fc-manage --directory --build
  # Short form:
  $ sudo fc-manage -eb

.. _nixos-custom-modules:

Custom NixOS-native configuration
---------------------------------

You can put custom NixOS configuration (called modules) in
:file:`/etc/local/nixos`. See :file:`custom.nix.example` for the basic structure
of a NixOS module. All options offered by NixOS and our platform code can be set
there.

.. warning::

  Care must be taken to avoid breaking the system.
  Overriding options already set by the platform can be dangerous.

Run ``sudo fc-manage -b`` to activate the changes (**may restart services!**).

For more information about writing NixOS modules, refer to the
`NixOS manual <https://nixos.org/nixos/manual/index.html#sec-writing-modules>`_

Look up NixOS options here, with channel *22.05* selected:

`<https://nixos.org/nixos/options.html>`_
