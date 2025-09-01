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
  inherit (lib)
    mkOption
    mkEnableOption
    mkOverride
    types
    optional
    optionalString
    ;
in
{
  options.flyingcircus.roles.open-webui = {
    enable = mkEnableOption "Enable the Flying Circus Open WebUI role";
    hostName = mkOption {
      default = "ai-chat.${config.flyingcircus.enc.parameters.resource_group}.fcio.net";
      defaultText = "ai-chat.<resource group>.fcio.net";
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
    usersNeedApproval = mkOption {
      default = false;
      type = types.bool;
      description = ''
        Configure whether new users require admin approval after
        their initial successful login. This approval can be given in the
        admin settings.'';
    };
    # expose through role config for better visibility
    environmentFile = options.services.open-webui.environmentFile;
    llmApiSecretFile = mkOption {
      example = "/etc/local/open-webui/secret";
      default = null;
      type = types.nullOr types.str;
      description = ''
        A file containing the authentication secret for the Flying
        Circus AI Provider.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.open-webui = {
      enable = true;
      host = head fclib.network.srv.v4.addresses;
      environment = {
        ENABLE_SIGNUP = "false";
        ENABLE_LOGIN_FORM = "false";
        ENABLE_OAUTH_SIGNUP = "true";
        OAUTH_CLIENT_ID = "${config.networking.hostName}_open-webui";
        OPENID_PROVIDER_URL = "https://auth.flyingcircus.io/realms/fcio/.well-known/openid-configuration";
        OAUTH_PROVIDER_NAME = "FCIO";
        OAUTH_MERGE_ACCOUNTS_BY_EMAIL = "true";
        # manage admin approval of new users from OIDC
        DEFAULT_USER_ROLE = if cfg.usersNeedApproval then "pending" else "user";
        # XXX this gets written into the nix store – acceptable?
        OAUTH_CLIENT_SECRET = fclib.derivePasswordForHost "oidc_open-webui";

        OPENAI_API_BASE_URLS = cfg.llmApiUrl;

        # Normally, openwebui would persist certain credentials, like OPENAI_API_KEY,
        # into the database, never updating it again on changes.
        # We do *not* want that and assume convergent configuration behaviour, so
        # let's disable this.
        ENABLE_PERSISTENT_CONFIG = "False";
      };
      # Having a dedicated file only containing that secret would be neat though.
      environmentFile = cfg.environmentFile;
    };

    systemd.services.open-webui.serviceConfig = {
      LoadCredential = optional (cfg.llmApiSecretFile != null) "OPENAI_API_KEYS:${cfg.llmApiSecretFile}";
      ExecStart =
        let
          execStart = pkgs.writeShellScriptBin "open-webui-start" ''
            ${optionalString (
              cfg.llmApiSecretFile != null
            ) "export OPENAI_API_KEYS=$(<$CREDENTIALS_DIRECTORY/OPENAI_API_KEYS)"}
            exec ${lib.getExe scfg.package} serve --host "${scfg.host}" --port ${toString scfg.port}
          '';
        in
        mkOverride 90 (lib.getExe execStart);
    };

    flyingcircus.localConfigDirs.open-webui = {
      dir = "/etc/local/open-webui";
    };

    flyingcircus.services.nginx = {
      enable = true;
      virtualHosts.${cfg.hostName} = {
        enableACME = true;
        forceSSL = true;
        locations = {
          "/" = {
            proxyPass = "http://${scfg.host}:${toString scfg.port}";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_read_timeout 1200s;
              proxy_buffering off;
            '';
          };
        };
      };
    };
  };

}
