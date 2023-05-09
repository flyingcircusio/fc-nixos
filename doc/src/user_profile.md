(nixos-user-package-management)=

# User Package Management

NixOS allows users to manage packages independently from the base system.
Service and normal users can install packages from nixpkgs or other sources
in their *user profile*. This is a powerful mechanism to tailor an application's
runtime environment to the exact needs of the deployment.
You can also use this approach to install tools that you want to use
interactively.

User packages are installed to {file}`~/.nix-profile`,
consisting of the usual subdirectories like *bin*, *include*, *lib*, etc

Installing packages that are already present in the system environment is safe.
This doesn't use additional space if it's exactly the same package.
Other versions, newer or older than system packages, can be installed without
conflicts.

(user-env)=

## Custom User Environments

The user profile can be customized by building an environment with `buildEnv`
and installing it. Packages from arbitrary sources can be mixed and pinned
to specific versions.

```{highlight} default
:linenothreshold: 3
```

Create a file like {file}`myproject_env.nix` which specifies the packages to be installed:

```
let
  # Imports. Which package sources should be used?
  # Use a pinned platform version
  # pkgs = import (fetchTarball https://hydra.flyingcircus.io/build/176012/download/1/nixexprs.tar.xz) {};
  # ...or just use the current version of the platform
  pkgs = import <nixpkgs> {};
in
pkgs.buildEnv {
  name = "myproject-env";
  paths = with pkgs; [
    libjpeg
    zlib
    ffmpeg
    nodejs_18
    electron
  ];
  extraOutputsToInstall = [ "dev" ];
}
```

The code shown above defines an environment with 5 packages installed from a
specific build of our NixOS 22.05 platform.
The pinned version can be newer or older than the installed system version.

Pinning the version of the import prevents unwanted changes in your
application's dependencies but you are responsible for updating
the imports to get security fixes.

We recommend to keep the pinned version close to the system version to get the
latest security fixes. NixOS re-uses packages if the wanted version is already
in the Nix store, saving disk space and reducing installation time.

The URL for the current release can be found in the {ref}`changelog` for the
22.05 platform.

If you want to try NixOS unstable with the newest packages, get the URL from the channel:

```
$ curl -w "%{url_effective}\n" -I -L -s -S $URL -o /dev/null https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz
https://releases.nixos.org/nixos/unstable/nixos-22.11pre391680.4a01ca36d6b/nixexprs.tar.xz
```

Note that the unstable channel may be broken and that upstream NixOS channels
don't have some additional packages we provide on our platform.

Older NixOS versions than 22.05 usually don't get security updates anymore.

Links to all platform builds for 22.05 can be found here:

<https://hydra.flyingcircus.io/job/flyingcircus/fc-22.05-production/release>

See <https://nixos.org/nixos/packages.html> for a list of packages.
Use the *attribute name* from the list and include it in `paths`.
The *attribute name* can differ from the *package name*.
For some packages, multiple versions are available.

Dry-run this expression with:

```
nix-build myproject_env.nix
```

A {file}`result` symlink now points to the generated environment. It can be
inspected and used manually, but is not yet an active part of the user profile.

Run

```
nix-env -i -f myproject_env.nix
```

to install the env in your profile. Now its binaries are available in PATH
and libraries/include files should get found by the compiler.

To update, install the environment again with the same command.
This picks up changes in {file}`myproject_env.nix` and package updates
(if the imports are not pinned to a specific version).

### Collisions With Existing Packages

Packages included in an environment can collide with packages from other environments
or with separately installed packages (we recommend not to do this).

You may encounter an error like this:

```
$ nix-env -if myproject_env.nix
installing 'myproject-env'
building '/nix/store/c3qwfxvdhjgirvzxdhc2h0wpa59fplvk-user-environment.drv'...
error: packages '/nix/store/s1vqsx5jd7xxq3ihwxz4sc6h1fwnh3v1-myproject-env/lib/libz.so' and '/nix/store/iiymx8j7nlar3gc23lfkcscvr61fng8s-zlib-1.2.11/lib/libz.so' have the same priority 5; use 'nix-env --set-flag priority NUMBER INSTALLED_PKGNAME' to change the priority of one of the conflicting packages (0 being the highest priority)
builder for '/nix/store/c3qwfxvdhjgirvzxdhc2h0wpa59fplvk-user-environment.drv' failed with exit code 1
error: build of '/nix/store/c3qwfxvdhjgirvzxdhc2h0wpa59fplvk-user-environment.drv' failed
```

You can check for potential collisions by viewing the list of packages in the user profile:

```
nix-env -q --installed
```

To avoid/resolve conflicts, remove the package and install the user env afterwards:

```
nix-env -e zlib-1.2.11
nix-env -if myproject_env.nix
```

### Multiple Package Outputs

Packages can have multiple "outputs" which means that not all files are
installed by default. If you want to install libraries to build against,
including `dev` in `extraOutputsToInstall` should be sufficient.
You can check which outputs are available with the following command:

```
nix show-derivation -f '<nixpkgs>' zlib | jq '.[].env.outputs'
```

This shows the outputs for `zlib`: `out`, `dev` and `static`. `-f` sets
the inspected NixOS version, which can be an URL like in {file}`myproject_env.nix`.

Assume we have an user env with just `zlib`. If `extraOutputsToInstall`
is empty, these files would be installed:

```
$ nix-build myproject_env.nix && tree -l result
/nix/store/s1vqsx5jd7xxq3ihwxz4sc6h1fwnh3v1-myproject-env
result
├── lib -> /nix/store/iiymx8j7nlar3gc23lfkcscvr61fng8s-zlib-1.2.11/lib
│   ├── libz.so -> libz.so.1.2.11
│   ├── libz.so.1 -> libz.so.1.2.11
│   └── libz.so.1.2.11
└── share -> /nix/store/iiymx8j7nlar3gc23lfkcscvr61fng8s-zlib-1.2.11/share
    └── man
        └── man3
            └── zlib.3.gz
```

If you add `dev` to `extraOutputsToInstall`, `include` and `lib/pkgconfig`
would be installed, too:

```
$ nix-build myproject_env.nix && tree -l result
/nix/store/a078dzvn7w7pp3mn0gxig8mpc14p2g4s-myproject-env
result
├── include -> /nix/store/ww7601vx7qrcwwfnwzs1cwwx6zcqdjz3-zlib-1.2.11-dev/include
│   ├── zconf.h
│   └── zlib.h
├── lib
│   ├── libz.so -> /nix/store/iiymx8j7nlar3gc23lfkcscvr61fng8s-zlib-1.2.11/lib/libz.so
│   ├── libz.so.1 -> /nix/store/iiymx8j7nlar3gc23lfkcscvr61fng8s-zlib-1.2.11/lib/libz.so.1
│   ├── libz.so.1.2.11 -> /nix/store/iiymx8j7nlar3gc23lfkcscvr61fng8s-zlib-1.2.11/lib/libz.so.1.2.11
│   └── pkgconfig -> /nix/store/ww7601vx7qrcwwfnwzs1cwwx6zcqdjz3-zlib-1.2.11-dev/lib/pkgconfig
│       └── zlib.pc
└── share -> /nix/store/iiymx8j7nlar3gc23lfkcscvr61fng8s-zlib-1.2.11/share
    └── man
        └── man3
            └── zlib.3.gz
```

### Mixing Packages From Different Sources

You can import packages from different NixOS versions or other sources:

```
let
  pkgs = import <nixpkgs> {};
  pkgsUnstable = import (fetchTarball https://releases.nixos.org/nixos/unstable/nixos-22.11pre391680.4a01ca36d6b/nixexprs.tar.xz) {};
in
pkgs.buildEnv {
  name = "myproject-env";
  paths = with pkgs; [
    pkgsUnstable.libjpeg
    zlib
  ];
  extraOutputsToInstall = [ "dev" ];
}
```

This installs the `zlib` from the platform NixOS version but `libjpeg` from NixOS unstable (here 22.11pre).

% XXX list env vars

% XXX Custom shell initializaton

% XXX Fitting the RPATH of 3rd-party binary objects
