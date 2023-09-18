{
  outputs = { self, ...}: let
    versions = builtins.fromJSON (builtins.readFile ./versions.json);
    nixpkgs = let
      inherit (versions.nixpkgs) owner repo rev;
    in builtins.getFlake "github:${owner}/${repo}/${rev}";

    inherit (nixpkgs) lib;
    nixpkgsConfig = import ./nixpkgs-config.nix;

    pkgsFor = system: import nixpkgs {
      inherit system;
      overlays = [ self.overlays.default ];
      config = {
        inherit (nixpkgsConfig) permittedInsecurePackages;
      };
    };

    forAllSystems = lib.genAttrs lib.systems.flakeExposed;
  in {
    overlays.default = import ./pkgs/overlay.nix;
    nixosModules.default = import ./nixos/default.nix;

    legacyPackages = forAllSystems (system: import ./. {
      inherit nixpkgs system;
      overlays = [ self.overlays.default ];
      config = {
        inherit (nixpkgsConfig) permittedInsecurePackages;
      };
    });

    packages = forAllSystems (system: let
      pkgs = pkgsFor system;
    in {
      options = let
        testConfigFor = system: let
          pkgs = pkgsFor system;
          versions = import ./versions.nix { inherit pkgs; };
          testlib = import ./tests/testlib.nix { inherit  (pkgs) lib; };
        in lib.nixosSystem {
          inherit pkgs system;
          specialArgs.nixos-mailserver = versions.nixos-mailserver;

          modules = [
            {
              options.virtualisation.vlans = lib.mkOption {
                type = lib.types.anything;
                default = [];
              };

              config.networking.domain = "test.fcio.net";

              imports = [
                (testlib.fcConfig {
                  id = 1;
                  net.fe = true;
                  extraEncParameters.environment_url = "test.fcio.net";
                })
              ];
            }
          ];
        };

        rawOpts = lib.optionAttrSetToDocList (testConfigFor system).options;

        substSpecial = x:
          if lib.isDerivation x then { _type = "derivation"; name = x.name; }
          else if builtins.isAttrs x then lib.mapAttrs (name: substSpecial) x
          else if builtins.isList x then map substSpecial x
          else if lib.isFunction x then "<function>"
          else x;

        filteredOpts = lib.filter (opt: opt.visible && !opt.internal) rawOpts;
        optionsList = lib.flip map filteredOpts
          (opt: opt
            // lib.optionalAttrs (opt ? example) { example = substSpecial opt.example; }
            // lib.optionalAttrs (opt ? default) { default = substSpecial opt.default; }
            // lib.optionalAttrs (opt ? type) { type = substSpecial opt.type; }
          );

        optionsNix = builtins.listToAttrs (map (o: { name = o.name; value = removeAttrs o ["name" "visible" "internal"]; }) optionsList);
        finalOptions = lib.mapAttrsToList (name: option: option // { inherit name; }) optionsNix;
      in pkgs.writeText "options.json" (builtins.unsafeDiscardStringContext (builtins.toJSON finalOptions));
    });
  };
}
