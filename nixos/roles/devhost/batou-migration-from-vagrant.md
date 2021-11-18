# Migrating a batou Vagrant-based environment to the container-based `devhost`


## Update appenv and batou (beta)

> batou 2.3 is currently under development but already usable.


```
curl https://raw.githubusercontent.com/flyingcircusio/batou/master/appenv.py -o appenv
rm batou; ln -sf appenv batou
chmod +x appenv
```

Adapt your `requirements.txt`:

```
batou @ https://github.com/flyingcircusio/batou/archive/e04328df988911f8325be1aab1ced79aacce9f47.zip#sha256=5a25999ebce236373851980ea8c7a08ee6e60ba89662a249fd7513c3f01097a6
batou_ext @ https://github.com/flyingcircusio/batou_ext/archive/4188a855b87b11c11ef425dd85253143f207279d.zip#sha256=1cf585cf5f9bbf078f0e448669d96c285724cba6dc71ba63df739a515abd1a2c
```

Update your lockfile:

```
./appenv update-lockfile
```

## Migrate the environment configuration


* Create a new directory `environments/dev`

* Move (and rename) the existing environment config file to `environments/dev/environment.cfg`

Here's a template which you can use to adjust the environment config:

```
[environment]
service_user = s-dev
platform = nixos
update_method = rsync

[provisioner:default]
method = fc-nixos-dev-container
host = largo.fcdev.fcio.net
# in the future pinned from fc-21.09-production
# updatable through a curl command
# for now from our PR branch:
channel = https://hydra.flyingcircus.io/build/112949/download/1/nixexprs.tar.xz

[host:container]
provision-dynamic-hostname = True
provision-aliases =
	www
components =
	...

[component:XXX]
frontend_address = {{host.aliases.www}}:443
```

Notes about the template:

* the `[environment]` can be taken as is
* the `[provisioner]` needs to choose a host and an appropriate (pinned) channel
* your existing `[host]` sections usually need to be adjusted by adding the `provision-dynamic-hostname` flag and adding aliases for virtual HTTP hosts that should be accessible from the outside
* the `[component]` sections need to use the aliases and dynamically resolve them for the aliases

* Rename the secrets file to adapt to the new environment name (`secrets/dev.cfg` in this case).

## Adapt provisioning

* Delete the original `Vagrantfile`.

* If you have a custom `provision.nix` then move it to `environments/dev/provision.nix`.

* Review `provision.nix`. This should typically only require activating selected
  roles and no further environment adjustments like users or directories that
  were missing in Vagrant.

* Place a provision script in `environments/dev/provision.sh`:

```
COPY provision.nix /etc/local/nixos/provision-container.nix
```

## Run the deployment

Now you can run the deployment:

```
$ ./batou deploy dev
```

## Edge cases

* The update to batou 2.3 implies a number of migration steps for the
  deploymnt that are not specific to containers (require_v6, default/default_config_string, attributes without proper Attribute declaration are not mapped 
  any longer)

