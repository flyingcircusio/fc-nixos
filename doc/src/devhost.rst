.. _nixos-devhost:

Development Host
==========================

The ``devhost`` role is a flexible way to run multiple development deployments
using slim VMs on a single powerful, physical machine on our public infrastructure.


Rationale
---------

Why not run development deployments on my local machine?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Your resources may be too limited for larger projects: RAM, CPU, Disk
* Multi-machine deployments require extra effort to avoid conflicting resources.
* External access for colleagues and customers is not easily possible.

Why not run development deployments with a desktop virtualization tool like VirtualBox and Vagrant?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Your resources may be even more limited with the overhead of running additional VMs.
* External access for colleagues and customers is also not possible.
* Quality of Vagrant boxes proved too hard to ensure properly for a long time -
  our dev VM-based approach has a much higher coverage with automated
  testing and a smaller chance to result in unexpected non-working conditions.
* Using x86-based VMs is not possible on platforms like Apple M-Series.

Why not use persistent development environments using virtual machines in the Flying Circus platform?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Resource usage can grow quickly with the number of developers and become increasingly prohibitive.
* Less flexible and higher turnaround times to set up new environments: every
  environment requires proper configuration of public DNS and similar resources
  which only has to happen once for a development host.

What are the benefits of using the ``devhost`` role?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* A single large host (or virtual machine) can provide sufficient power to run
  parallel tests quickly and exceed RAM usage limits of local machines.

* Integration with `batou
  <https://batou.readthedocs.org>`_ supports "single button" deployment
  options for immediate personal environments without maintaining multiple
  environment definitions per developer.

* Allow colleagues to access the same development VMs to assist debugging.

* Proper pinning of platform releases to ensure repeatability.

* Fewer dependencies on the work stations -- no need to install Virtualbox,
  Vagrant and additional plugins.

* Dynamically and quickly create new temporary environments for customer
  validation.

* Allow customers and colleagues to access preview environments with
  automatic Let's Encrypt integration and instantaneous access using
  DNS wildcards from any domain.

* Automatic clean up of unused environments.

Setup
-----

1. Create a new resource group to grant/limit access for your developers.
   Developers need the ``login`` permission to interact with the devhost.

2. You need a physical machine with sufficient resources (CPU, RAM, SSD) and
   select the ``devhost`` role.

3. The machine needs to be assigned a public IP address (v4 and v6 are
   supported).

4. Choose a public domain name (e.g. ``dev.example.com``) and register it as
   a CNAME for the VM's public interface, i.e. set
   ``dev.example.com CNAME mydev00.fe.rzob.fcio.net``.

5. Add a wildcard DNS for all subdomains within the chosen public domain name,
   i.e. set ``*.dev.example.com CNAME mydev00.fe.rzob.fcio.net``.

4. Add the ``publicAddress`` option to the NixOS configuration on the host,
   e.g. in :file:`/etc/local/nixos/devhost.nix` and run :command:`fc-manage -b`:

   .. code-block:: Nix

       { ... }:
       {
         flyingcircus.roles.devhost.publicAddress = "dev.example.com";
       }


Configuring batou deployments
-----------------------------

batou (starting from 2.4) supports a specific provisioning mode that supports
defining environments based on VMs organized by the devhost role.
A development environment (e.g. named ``dev``) would typically look like this:

.. code-block:: sh

   $ mkdir -p environments/dev
   $ cat >> environments/dev/environment.cfg <<__EOF__
   [environment]
   service_user = s-dev
   platform = nixos
   update_method = rsync

   [provisioner:default]
   method = fc-nixos-dev-vm
   host = dev.example.com
   # URL to the release metadata file. See below for an explanation
   release = https://my.flyingcircus.io/releases/metadata/fc-24.05-staging
   # Older batou versions (<=2.5.0) only support the hydra_eval attribute instead of `release`
   # hydra-eval = 309628

   [host:myvm]
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
     flyingcircus.roles.postgresql12.enable = true;
   }
   __EOF__

   $ cat >> environments/dev/provision.sh <<__EOF__
   COPY ../../../sourcecode /srv/s-dev/
   ECHO $COMPONENT_MANAGEDMYSQL_ADMIN_PASSWORD /etc/local/nixos/mysql.passwd
   __EOF__

Then, to deploy to your VM simply run:

.. code-block:: sh

   $ ./batou deploy dev

This will create, start and configure the VM as necessary.

If you want to rebuild your VM from scratch, you can run:

.. code-block:: sh

   $ ./batou deploy --provision-rebuild dev

The URL for the release metadata file can be looked up in our changelog.
The general format of these URLs is ``https://my.flyingcircus.io/releases/metadata/<environment_name>/<release_name>``.
``release_name`` is optional, and if not specified the latest version of the environment will be deployed with each batou deployment.
This is probably what you want.
Only platform releases starting from 23.11 are supported for development VMs.

Using the ``provision-dynamic-hostname`` switch will result in development VMs
receiving a random hostname based on your local batou checkout. This is the
core feature that allows using the same environment (e.g. ``dev``) for multiple
developers independently. If you leave this off then the VM name will be
exactly what is written in the environment.

Using the ``provision-aliases`` will create virtual hosts on the dev server that
become available as ``<alias>.<vm>.dev.example.com`` and are protected
with Let's Encrypt certificates automatically. They are intended to pass
through access to the UI of your applications and act similar to port forwards
for port 443 -> 443. You should use self-signed certificates within the
vms. (``batou_ext.ssl.Certifiate`` already allows switching between
custom )

As the development VMs are not managed by our inventory you need to place relevant
information about roles in a Nix expression file. You can then use a
provisioning script :file:`provision.sh` to customize the VMs during
provisioning. :command:`fc-manage` will be called automatically for you. In the
provision script you can use :command:`COPY` to copy local files (relative to
the environment directory) to the VMs (relative to the root),
use :command:`RUN` to run commands in the VMs (as root)
or :command:`ECHO` to output a local comand (and access environment variables
carrying secrets) into a remote file.


Connecting to the VM(s)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

batou automatically maintains a number of :file:`ssh_config` files as well as a
specific insecure key pair for each environment so you can easily access the VM via SSH.

For example, to access the VM ``myvm`` in the ``dev`` environment
you can simply run:

.. code-block:: sh

   $ ssh -F ssh_config_dev myvm

The environment works similar to our regular platform: the user login
(``developer``) represents a human user and the services are installed in the
service user (``s-dev``).

Writing provision scripts
~~~~~~~~~~~~~~~~~~~~~~~~~

For early changes to the target dev VM that aren't part of the deployment
but are expected by the deployment to be prepared by "the environment" you
can write a provision script for which a number of special functions.

.. code-block:: sh
    :caption: environments/dev/provision.sh

    COPY sample.txt /tmp/
    ECHO $COMPONENT_MANAGEDMYSQL_ADMIN_PASSWORD /etc/local/mysql/mysql.passwd
    RUN mkdir /tmp/some/directory

The script will execute on the machine where you started batou and can interact
with the VM through the following features:

.. function:: COPY <local path> <remote path>

   Copy a local file to a destination in the VM.

   The local path is relative to the environment's directory
   (where `provision.sh` is placed). The remote path must be absolute.

.. function:: RUN cmd arg1 arg2

   Execute a command as root in the VM.

   .. note::

      Using redirections like `>` will not work here.

.. function:: ECHO <expression> <remote path>

    Execute an expression locally and store its output in a remote path.

    This can be used to evaluate a variable from the environment locally
    and store its result in the VM.

Sometimes it may be necessary to seed data from the environment (like secrets)
early to the provisioner in order to set predictable/repeatable passwords
for system services. We therefore provide a number of variables to the
provision script:

``COMPONENT_<COMPONENT_NAME>_<ATTRIBUTE_NAME>``
    All overrides and secrets for all components in the environment.
``PROVISION_CONTAINER``
    The name of the VM being provisioned.
``PROVISION_HOST``
    The name of the ``devhost`` that the VM is being provisioned onto.
``PROVISION_CHANNEL``
    The NixOS channel URL being used.
``PROVISION_IMAGE``
    The NixOS devhost image being used to provision the VM on its first start.
``PROVISION_ALIASES``
    The list of aliases.
``SSH_CONFIG``
    The path to the locally generated SSH config file.

.. note::

    Provision scripts should be kept extremely small. The bulk of the deployment
    should be handled using batou proper.

.. note::

    batou continues deployment under certain conditions after an error during
    provisioning. This is explicitly shown and annotated with a corresponding
    warning. In some situations a partially failed deployment may have created
    an environment that is broken but needs the deployment to run to be fixed
    automatically.


Syncing development code into the VM
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Often you will be editing code using your local editor or IDE and need it to
be synced to the target VM quickly without much repeated effort.

We recommend to integrate this using one or more rsync commands of this form:

.. code-block:: sh

   BATOUDIR=/Users/bob/code/mybatourepo
   TARGET=sourcecode
   SOURCE=/Users/bob/code/myappcode
   rsync -avz --delete --exclude=.git --rsh='ssh -F ${BATOUDIR}/ssh_config_dev' --rsync-path='sudo -u s-dev rsync' ${SOURCE}/ myvm:/srv/s-dev/${TARGET}

You can then use this command either with an ``on-save`` hook in your editor or
by using a tool that responds to changes in your filesystem (like )

In the future there will be optimized support for this behaviour in batou.

To sync code that is currently being developed on (and assuming you are using
an editor / IDE on your local machine)


Maintenance
-----------

To manually delete a VM you can use the build script's ``destroy`` action:

.. code-block:: sh

   $ fc-devhost destroy $vmname

To list all VMs running on a devhost with their users and creation date:

.. code-block:: sh

   $ fc-devhost ls -l

All other commands can be seen with:

.. code-block:: sh

   $ fc-devhost --help

If a VM hangs up, it's possible to see their log in ``/var/lib/devhost/$vmname/log``


Known issues
------------

* Devhost VMs currently does no (properly) support IPv6 so deployments need to disable IPv6 resolution for internal and public
  services.
