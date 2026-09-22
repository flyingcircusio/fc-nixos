import ./make-test-python.nix (
  { testlib, ... }:

  {
    name = "crowdsec";

    nodes.machine =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
      in
      {
        imports = [
          (testlib.fcConfig { })
        ];

        specialisation.withWaf.configuration = {
          flyingcircus.roles.crowdsec.waf.enable = true;
          # Explicitly disable crowdsec-setup, as it needs internet for WAF.
          systemd.services.crowdsec-setup.enable = false;
        };

        flyingcircus.roles.crowdsec = {
          enable = true;
          enrollKeyFile = "/etc/crowdsec-api-key";
        };
        services.crowdsec.settings = {
          config.api.server.online_client.credentials_path = lib.mkForce null;
          config.cscli = {
            hub_branch = "test";
            __hub_url_template__ = "http://127.0.0.1:49200/%s/%s";
          };
        };
        services.crowdsec.hub.collections = lib.mkForce [ ];
        environment.etc."crowdsec-api-key".text = "";

        # Use a second webserver to reliably serve the hub
        services.caddy = {
          enable = true;

          virtualHosts =
            let
              hub = pkgs.stdenv.mkDerivation {
                name = "hub-index-json";
                src = pkgs.fetchurl {
                  url = "https://raw.githubusercontent.com/TornaxO7/nixpkgs/5eb6afeb3d4619702e2d590bf7db468f7303571c/nixos/tests/crowdsec/data/hub/.index.json";
                  hash = "sha256-6dotUcIZRzGcNKo6FWpJ7UOOoQ6y5ZDQ3jgVx03dsjk=";
                };
                dontUnpack = true;
                dontBuild = true;
                installPhase = ''
                  mkdir -p $out
                  cp $src $out/.index.json
                '';
              };

            in
            {
              "http://127.0.0.1:49200".extraConfig = ''
                handle_path /test/* {
                  root ${hub}
                  file_server
                }
              '';
            };
        };
        flyingcircus.services.nginx.enable = true;
        flyingcircus.services.nginx.virtualHosts = {
          machine = {
            root = pkgs.writeTextFile {
              name = "nginx-root-initial";
              text = "initial content\n";
              destination = "/index.html";
            };
          };
        };
      };
    testScript = { nodes, ... }: ''
      def switch_specialisation(name, expected_fail: bool):
          path = "${nodes.machine.system.build.toplevel}/bin/switch-to-configuration" \
            if name is None \
            else f"${nodes.machine.system.build.toplevel}/specialisation/{name}/bin/switch-to-configuration"
          if expected_fail:
            machine.fail(f"{path} test")
          else:
            machine.succeed(f"{path} test")

      def wait_for_unit_property(unit: str, property: str, wanted_state: str, timeout: int):
        def check_active(_last_try: bool) -> bool:
            state = machine.get_unit_property(unit, property)
            return state == wanted_state

        with machine.nested(
            f"waiting for unit {unit} property {property}"
        ):
            retry(check_active, timeout)


      start_all()

      machine.wait_for_unit("caddy.service")
      machine.wait_for_unit("crowdsec.service")
      machine.wait_for_unit("crowdsec-firewall-bouncer.service")

      switch_specialisation("withWaf", False)
      # Check that register+setup exited successfully
      wait_for_unit_property("crowdsec-nginx-bouncer-register.service", "ActiveState", "inactive", 60)
      wait_for_unit_property("crowdsec-nginx-bouncer-register.service", "ExecMainStatus", "0", 60)
      wait_for_unit_property("crowdsec-nginx-bouncer-setup.service", "ActiveState", "inactive", 60)
      wait_for_unit_property("crowdsec-nginx-bouncer-setup.service", "ExecMainStatus", "0", 60)
      machine.wait_for_unit("nginx.service")
    '';
  }
)
