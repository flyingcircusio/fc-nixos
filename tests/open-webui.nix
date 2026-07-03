import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
  in
  {
    name = "open-webui";
    nodes.machine =
      {
        pkgs,
        lib,
        config,
        ...
      }:
      {
        imports = [ (testlib.fcConfig { id = 1; }) ];
        networking.domain = "fcio.net";
        networking.extraHosts = ''
          ${builtins.head config.fclib.network.srv.v4.addresses} machine
          ${builtins.head config.fclib.network.srv.v6.addresses} machine
        '';

        flyingcircus.roles.open-webui.enable = true;

        environment.etc."local/open-webui/secret".text = "imasecret";

        # cannot download sentence transformers model without network
        # connection.
        services.open-webui.environment = {
          RAG_EMBEDDING_MODEL = "";
          RAG_EMBEDDING_ENGINE = "ollama";
        };

        services.nginx.virtualHosts."ai-chat.test.fcio.net" = {
          enableACME = lib.mkForce false;
          forceSSL = lib.mkForce false;
        };
      };
    testScript = ''
      machine.wait_for_unit("multi-user.target")

      # open webui is slow to boot, but should eventually respond
      # with http status 200
      machine.wait_for_open_port(8080, "192.168.3.1", timeout=160)
      machine.wait_until_succeeds("curl -f http://192.168.3.1:8080")
    '';
  }
)
