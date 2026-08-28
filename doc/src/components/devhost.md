# Development Host { #nixos-devhost }

The `devhost` role is a flexible way to run multiple development deployments
using slim VMs on a single powerful, physical machine on our public infrastructure.

## Rationale

### Why not run development deployments on my local machine?

- Your resources may be too limited for larger projects: RAM, CPU, Disk
- Multi-machine deployments require extra effort to avoid conflicting resources.
- External access for colleagues and customers is not easily possible.

### Why not run development deployments with a desktop virtualization tool like VirtualBox and Vagrant?

- Your resources may be even more limited with the overhead of running additional VMs.
- External access for colleagues and customers is also not possible.
- Quality of Vagrant boxes proved too hard to ensure properly for a long time -
  our dev VM-based approach has a much higher coverage with automated
  testing and a smaller chance to result in unexpected non-working conditions.
- Using x86-based VMs is not possible on platforms like Apple M-Series.

### Why not use persistent development environments using virtual machines in the Flying Circus platform?

- Resource usage can grow quickly with the number of developers and become increasingly prohibitive.
- Less flexible and higher turnaround times to set up new environments: every
  environment requires proper configuration of public DNS and similar resources
  which only has to happen once for a development host.

### What are the benefits of using the `devhost` role?

- A single large host (or virtual machine) can provide sufficient power to run
  parallel tests quickly and exceed RAM usage limits of local machines.
- Integration with [batou](https://batou.readthedocs.org) supports "single button" deployment
  options for immediate personal environments without maintaining multiple
  environment definitions per developer.
- Allow colleagues to access the same development VMs to assist debugging.
- Proper pinning of platform releases to ensure repeatability.
- Fewer dependencies on the work stations -- no need to install Virtualbox,
  Vagrant and additional plugins.
- Dynamically and quickly create new temporary environments for customer
  validation.
- Allow customers and colleagues to access preview environments with
  automatic Let's Encrypt integration and instantaneous access using
  DNS wildcards from any domain.
- Automatic clean up of unused environments.

## Setup

1. Create a new resource group to grant/limit access for your developers.
   Developers need the `login` permission to interact with the devhost.
2. You need a physical machine with sufficient resources (CPU, RAM, SSD) and
   select the `devhost` role.
3. The machine needs to be assigned a public IP address (v4 and v6 are
   supported).
4. Choose a public domain name (e.g. `dev.example.com`) and register it as
   a CNAME for the VM's public interface, i.e. set
   `dev.example.com CNAME mydev00.fe.rzob.fcio.net`.
5. Add a wildcard DNS for all subdomains within the chosen public domain name,
   i.e. set `*.dev.example.com CNAME mydev00.fe.rzob.fcio.net`.

4) Add the `publicAddress` option to the NixOS configuration on the host,
   e.g. in `/etc/local/nixos/devhost.nix` and run `fc-manage switch`:

   ```Nix
   { ... }:
   {
     flyingcircus.roles.devhost.publicAddress = "dev.example.com";
   }
   ```

5) Optional: Adjust VM shutdown/deletion timeouts.

   ```Nix
   { ... }:
   {
     flyingcircus.roles.devhost.virtualMachineOptions = {
       shutdownDays = 14;  # default
       deleteDays = 31;    # default
     };
   }
   ```

## Configuring batou deployments

batou (starting from 2.4) supports a specific provisioning mode that supports
defining environments based on VMs organized by the devhost role.
A development environment (e.g. named `dev`) would typically look like this:

```sh
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
release = https://my.flyingcircus.io/releases/metadata/fc-25.05-staging
# Older batou versions (<=2.5.0) only support the hydra_eval attribute instead of `release`
# hydra-eval = 309628
disk_size = 50G

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
  flyingcircus.roles.percona84.enable = true;
  flyingcircus.roles.postgresql17.enable = true;
}
__EOF__

$ cat >> environments/dev/provision.sh <<__EOF__
COPY ../../../sourcecode /srv/s-dev/
ECHO $COMPONENT_MANAGEDMYSQL_ADMIN_PASSWORD /etc/local/nixos/mysql.passwd
__EOF__
```

Then, to deploy to your VM simply run:

```sh
$ ./batou deploy dev
```

This will create, start and configure the VM as necessary.

If you want to rebuild your VM from scratch, you can run:

```sh
$ ./batou deploy --provision-rebuild dev
```

The URL for the release metadata file can be looked up in our changelog.
The general format of these URLs is `https://my.flyingcircus.io/releases/metadata/<environment_name>/<release_name>`.
`release_name` is optional, and if not specified the latest version of the environment will be deployed with each batou deployment.
This is probably what you want.  \
By default, batou will continue to update the environment of the target VM according to your metadata even after the initial bootstrap.
This enables updating existing devhost deployments just by adjusting metadata. To disable this behaviour,
set `update_channel = False` in the `provisioner` config section.  \
Only platform releases starting from 23.11 are supported for development VMs.

Using the `provision-dynamic-hostname` switch will result in development VMs
receiving a random hostname based on your local batou checkout. This is the
core feature that allows using the same environment (e.g. `dev`) for multiple
developers independently. If you leave this off then the VM name will be
exactly what is written in the environment.

Using the `provision-aliases` will create virtual hosts on the dev server that
become available as `<alias>.<vm>.dev.example.com` and are protected
with Let's Encrypt certificates automatically. They are intended to pass
through access to the UI of your applications and act similar to port forwards
for port 443 -> 443. You should use self-signed certificates within the
vms. (`batou_ext.ssl.Certificate` already allows switching between
custom certificates).

As the development VMs are not managed by our inventory you need to place relevant
information about roles in a Nix expression file. You can then use a
provisioning script `provision.sh` to customize the VMs during
provisioning. `fc-manage` will be called automatically for you. In the
provision script you can use `COPY` to copy local files (relative to
the environment directory) to the VMs (relative to the root),
use `RUN` to run commands in the VMs (as root)
or `ECHO` to output a local comand (and access environment variables
carrying secrets) into a remote file.

### Connecting to the VM(s)

batou automatically maintains a number of `ssh_config` files as well as a
specific insecure key pair for each environment so you can easily access the VM via SSH.

For example, to access the VM `myvm` in the `dev` environment
you can simply run:

```sh
$ ssh -F ssh_config_dev myvm
```

The environment works similar to our regular platform: the user login
(`developer`) represents a human user and the services are installed in the
service user (`s-dev`).

### Writing provision scripts

For early changes to the target dev VM that aren't part of the deployment
but are expected by the deployment to be prepared by "the environment" you
can write a provision script for which a number of special functions.

```sh
COPY sample.txt /tmp/
ECHO $COMPONENT_MANAGEDMYSQL_ADMIN_PASSWORD /etc/local/mysql/mysql.passwd
RUN mkdir /tmp/some/directory
```

The script will execute on the machine where you started batou and can interact
with the VM through the following features:




Sometimes it may be necessary to seed data from the environment (like secrets)
early to the provisioner in order to set predictable/repeatable passwords
for system services. We therefore provide a number of variables to the
provision script:

`COMPONENT_<COMPONENT_NAME>_<ATTRIBUTE_NAME>`

: All overrides and secrets for all components in the environment.

`PROVISION_CONTAINER`

: The name of the VM being provisioned.

`PROVISION_HOST`

: The name of the `devhost` that the VM is being provisioned onto.

`PROVISION_CHANNEL`

: The NixOS channel URL being used.

`PROVISION_IMAGE`

: The NixOS devhost image being used to provision the VM on its first start.

`PROVISION_ALIASES`

: The list of aliases.

`SSH_CONFIG`

: The path to the locally generated SSH config file.

!!! note
    Provision scripts should be kept extremely small. The bulk of the deployment
    should be handled using batou proper.

!!! note
    batou continues deployment under certain conditions after an error during
    provisioning. This is explicitly shown and annotated with a corresponding
    warning. In some situations a partially failed deployment may have created
    an environment that is broken but needs the deployment to run to be fixed
    automatically.

### Syncing development code into the VM

Often you will be editing code using your local editor or IDE and need it to
be synced to the target VM quickly without much repeated effort.

We recommend to integrate this using one or more rsync commands of this form:

```sh
BATOUDIR=/Users/bob/code/mybatourepo
TARGET=sourcecode
SOURCE=/Users/bob/code/myappcode
rsync -avz --delete --exclude=.git --rsh='ssh -F ${BATOUDIR}/ssh_config_dev' --rsync-path='sudo -u s-dev rsync' ${SOURCE}/ myvm:/srv/s-dev/${TARGET}
```

You can then use this command either with an `on-save` hook in your editor or
by using a tool that responds to changes in your filesystem (like )

In the future there will be optimized support for this behaviour in batou.

To sync code that is currently being developed on (and assuming you are using
an editor / IDE on your local machine)

## Maintenance

To manually delete a VM you can use the build script's `destroy` action:

```sh
$ fc-devhost destroy $vmname
```

To list all VMs running on a devhost with their users and creation date:

```sh
$ fc-devhost ls -l
```

All other commands can be seen with:

```sh
$ fc-devhost --help
```

If a VM hangs up, it's possible to see their log in `/var/lib/devhost/$vmname/log`

## Known issues

- Devhost VMs currently does no (properly) support IPv6 so deployments need to disable IPv6 resolution for internal and public
  services.
