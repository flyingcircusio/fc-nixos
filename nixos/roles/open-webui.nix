{
  config,
  options,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.flyingcircus.roles.open-webui;
  scfg = config.services.open-webui;
  fclib = config.fclib;
  inherit (builtins) head;
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.flyingcircus.roles.open-webui = {
    enable = mkEnableOption "Enable the Flying Circus Open WebUI role";
    hostName = mkOption {
      default = fclib.fqdn { vlan = "fe"; };
      type = types.str;
      description = ''
        Host name for the Open WebUI frontend.
        A Letsencrypt certificate is generated for it.
        Defaults to the FE FQDN.
      '';
      example = "chat.example.com";
    };
    llmApiUrl = mkOption {
      default = "https://api.ai.flyingcircus.io";
      type = types.str;
      description = ''
        Endpoint of the (OpenAI-style) LLM API used as main upstream AI provider.
        In most cases, this should NOT contain a trailing /.
      '';
    };
    # expose through role config for better visibility
    environmentFile = options.services.open-webui.environmentFile;
  };

  # TODO: role shall also configure an nginx with TLS (or webgateway?)
  config = lib.mkIf cfg.enable {
    services.open-webui = {
      enable = true;
      host = head fclib.network.srv.v4.addresses;
      environment = {
        #ENABLE_SIGNUP = "false";
        #ENABLE_LOGIN_FORM = "false";
        #ENABLE_OAUTH_SIGNUP = "true";
        #OAUTH_CLIENT_ID = "fc-ai-chat-FIXME";
        #OPENID_PROVIDER_URL = "https://auth.flyingcircus.io/realms/fcio/.well-known/openid-configuration";
        #OAUTH_PROVIDER_NAME = "FCIO";
        #OAUTH_MERGE_ACCOUNTS_BY_EMAIL = "true";

        OPENAI_API_BASE_URLS = cfg.llmApiUrl;

        # Normally, openwebui would persist certain credentials, like OPENAI_API_KEY,
        # into the database, never updating it again on changes.
        # We do *not* want that and assume convergent configuration behaviour, so
        # let's disable this.
        ENABLE_PERSISTENT_CONFIG = "False";
      };
      # FIXME: populate OAUTH secrets automatically
      # XXX: We assume for now that the API key is written into the secrets file
      # as an `OPENAI_API_KEY`.
      # Having a dedicated file only containing that secret would be neat though.
      environmentFile = cfg.environmentFile;
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts.${cfg.hostName} = {
        enableACME = true;
        forceSSL = true;
        locations = {
          "/" = {
            proxyPass = "http://${scfg.host}:${toString scfg.port}";
            extraConfig = ''
              proxy_read_timeout 1200s;
              proxy_buffering off;
            '';
          };
          "/ws/" = {
            proxyPass = "http://${scfg.host}:${toString scfg.port}";
            extraConfig = ''
              proxy_http_version 1.1;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
            '';
          };
        };
      };
    };

  };

}
