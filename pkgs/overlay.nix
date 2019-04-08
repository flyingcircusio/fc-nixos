self: super:

let
  versions = import ../versions.nix { pkgs = super; };
  pkgs-18_03 = import versions.nixos-18_03 {};

in {
  #
  # == our own stuff
  #
  fc = (import ./default.nix { pkgs = self; });

  #
  # == imports from older nixpkgs ==
  #
  inherit (pkgs-18_03)
    nodejs-9_x
    php56
    php56Packages;

  busybox = super.busybox.overrideAttrs (oldAttrs: {
      meta.priority = 10;
    });
  docsplit = super.callPackage ./docsplit { };
  influxdb = super.callPackage ./influxdb { };
  innotop = super.callPackage ./percona/innotop.nix { };

  mailx = super.callPackage ./mailx.nix { };
  mc = super.callPackage ./mc.nix { };
  mysql = super.mariadb;

  nginx = super.nginx.override {
    modules = [
      self.nginxModules.dav
      self.nginxModules.modsecurity
      self.nginxModules.moreheaders
      self.nginxModules.rtmp
    ];
  };

  # We use a (our) newer version than on upstream.
  vulnix = super.callPackage ./vulnix.nix {
    pythonPackages = self.python3Packages;
  };

}
