.. _nixos-devhost:

Development Container Host
==========================

The ``devhost`` role is intended to be a replacement for running local development instances of application deployments using containers on a virtual machine in our platform. 

.. note:: Previously you may have used Vagrant to run virtual machines
  for local development. However, due to the large resource requirements for more complex setups as well as to provide a workflow for users
  with the Apple M1 we are providing this role as an improved replacement.

Using the ``devhost`` role as for development environments has the following benefits:

* A single large host can provide sufficient power to run parallel tests
  quickly and exceed RAM usage limits of local machines.

* Multi-user development environments using `batou <https://batou.readthedocs.org>`_ are well-integrated for bootstrapping independent environments from the same definition without managing environments for every developer.

* Allow colleagues to access the same containers to assist debugging.

* Proper pinning of platform releases to ensure repeatability.

* Fewer dependencies on the work stations -- no need to install Virtualbox, 
  Vagrant and additional plugins.

* Dynamically and quickly create new temporary environments for customer 
  validation.

* Allow customers and colleagues to access preview environments with
  automatic Let's Encrypt integration and instantaneous access using
  DNS wildcards from any domain.

* Automatic clean up of unused environments)

Configuration
-------------

1. The virtual machine needs a public IP address (v4 and v6 are supported).

2. Choose a public domain name (e.g. ``dev.example.com``) and
   register this as a CNAME for the VMs public interface (e.g. ``dev.example.com CNAME myvm00.fe.rzob.fcio.net``).

3. Add a wildcard DNS for all subdomains within the chosen public domain name, e.g. ``*.dev.example.com CNAME myvm00.fe.rzob.fcio.net``.

4. Add the ``publicAddress`` option to the NixOS configuration on the host, e.g. in :file:`/etc/local/nixos/devhost.nix` and run :command:`fc-manage -b`:

.. code-block:: Nix

   { ... }:
   {
      flyingcircus.roles.devhost.publicAddress = "dev.example.com"
   }


Setting up batou environments
-----------------------------

batou (starting from 2.3) supports a specific provisioning mode that supports defining container based environments. A container environment (``dev``) would typically look like this:

.. code-block:: sh

   $ mkdir -p environments/dev
   $ cat >> environments/dev/environment.cfg <<__EOF__
   [environment]
   service_user = s-dev
   platform = nixos
   update_method = rsync

   [provisioner:default]
   method = fc-nixos-dev-container
   host = dev.example.com
   channel = https://hydra.flyingcircus.io/build/101493/download/1/nixexprs.tar.xz

   [host:container]
   provision-dynamic-hostname = True
   provision-aliases =
       app
   components =
       ...
   __EOF__

   $ cat >> environments/dev/provision.nix <<__EOF__
   { lib, pkgs, ... }:
   {
     flyingcircus.roles.webgateway.enable = true;
     flyingcircus.roles.redis.enable = true;
     flyingcircus.roles.percona80.enable = true;
     services.percona.rootPasswordFile = lib.mkForce "/etc/local/nixos/mysql-root-password";
     flyingcircus.roles.postgresql12.enable = true;
   }
   __EOF__

   $ cat >> environments/dev/provision.sh <<__EOF__
   COPY provision.nix /etc/local/nixos/provision-container.nix
   ECHO $COMPONENT_MANAGEDMYSQL_ADMIN_PASSWORD /etc/local/nixos/mysql-root-password
   __EOF__

Then, to deploy to your container simply run:

.. code-block:: sh

   $ ./batou deploy dev

This will create, start and configure the container as necessary. 

If you want to rebuild your container from scratch, you can run:

.. code-block:: sh

   $ ./batou deploy --provision-rebuild dev

The URLs for channels can be looked up in our changelog: each version is listed with a link to the appropriate channel. Only platform releases starting from 21.05 are supported for development containers, though!

Using the ``provision-dynamic-hostname`` switch will result in containers receiving a random hostname based on your local batou checkout. This is the core feature that allows using the same environment (e.g. ``dev``) for multiple developers independently. If you leave this off then the container name will be exactly what is written in the environment.

Using the ``provision-aliases`` will create virtual hosts on the dev server that become available as ``<alias>.<container>.dev.example.com`` and are protected with Let's Encrypt certificates automatically. They are intended to pass through access to the UI of your applications and act similar to port forwards for port 443 -> 443. You should use self-signed certificates within the containers. (``batou_ext.ssl.Certifiate`` already allows switching between custom )

As the containers are not managed by our inventory you need to place relevant information about roles in a Nix expression file. You can then use a provisioning script :file:`provision.sh` to customize the container during provisioning. :command:`fc-manage` will be called automatically for you. In the provision script you can use :command:`COPY` to copy local files (relative to the environment directory) to the container (relative to the root), use :command:`RUN` to run commands in the container (as root) or :command:`ECHO` to output a local comand (and access environment variables carrying secrets) into a remote file.




Connecting to the container
---------------------------

batou automatically maintains a number of :file:`ssh_config` files as well as a specific insecure key pair for each environment so you can easily access the container via SSH.

For example, to access the container ``mycontainer`` in the ``dev`` environment you can simply run:

.. code-block:: sh

   $ ssh -F ssh_config_dev mycontainer

The environment works similar to our regular platform: the user login (``developer``) represents a human user and the services are installed in the service user (``s-dev``).

Syncing development code into the container
-------------------------------------------



Maintenance
-----------

* 7d shutdown
* 30d deletion

* manual shutdown


