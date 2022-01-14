# Migrating a batou Vagrant-based environment to the container-based `devhost`

## Update appenv and batou (beta)

> batou 2.3 is currently under development but already usable.

```
curl https://raw.githubusercontent.com/flyingcircusio/batou/master/appenv.py -o appenv
rm batou; ln -sf appenv batou
chmod +x appenv
```

Adapt your `requirements.txt`:

> batou_ext is a package that is currently being developed in a floating style. At the time of this writing 
> you should check to get the most recent commit id for the batou-2.3.x branch:
> https://github.com/flyingcircusio/batou_ext/tree/batou-2.3.x
> replace the commit id in the content of the file below.

```
batou>=2.3b3
batou_ext @ https://github.com/flyingcircusio/batou_ext/archive/a875a4f7cfe8d53e56930f7c579b9430d8670cff.zip#sha256=48d44fb85315bfa61132e987daf0dcc4f4a118054357df451e9bb0d605a2ef12
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

If you want or need to sync (editable) source code before starting the deployment, use the `COPY` command:

```
COPY ../../../fc.directory /srv/s-dev/
```

If you want to initialize secrets with well-known secrets you can access all component overrides and secrets through environment variables and echo them into specific files in the container:

```
ECHO $COMPONENT_MANAGEDMYSQL_ADMIN_PASSWORD /etc/local/mysql/mysql-root-password
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
