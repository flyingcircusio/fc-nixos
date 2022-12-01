{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.gitlab;
  fclib = config.fclib;
  gitlabPackage = config.services.gitlab.packages.gitlab;
in

{
  options = with lib; {

    flyingcircus.roles.gitlab = {
      enable = mkEnableOption "Enable the Flying Circus GitLab role.";
      supportsContainers = fclib.mkDisableContainerSupport;


      enableDockerRegistry = mkEnableOption "Enable docker registry and GitLab integration";

      dockerHostName = mkOption {
        type = with types; nullOr str;
        description = "HTTP virtual host for the docker registry.";
        default = null;
        example = "docker.test.fcio.net";
      };

      hostName = mkOption {
        type = types.str;
        description = ''
          Public host name for the GitLab frontend.
          A Letsencrypt certificate is generated for it.
          Defaults to the FE FQDN.
        '';
        default = fclib.fqdn { vlan = "fe"; };
        example = "gitlab.test.fcio.net";
      };

      manageSecrets = mkOption {
        type = types.bool;
        description = ''
          Should secrets be generated automatically in their default locations?
          Set this to false if you want to manage secrets by yourself (via a deployment)
        '';
        default = true;
      };
    };
  };

  config = lib.mkMerge [

  (lib.mkIf cfg.enable {

    environment.systemPackages = with pkgs; [
      (writeScriptBin "gitlab-show-config" ''jq < /srv/gitlab/state/config/gitlab.yml'')
    ];

    # all logs to /var/log
    systemd.tmpfiles.rules = [
      "d /var/log/gitlab 0750 ${config.services.gitlab.user} ${config.services.gitlab.group} -"
      "L+ ${config.services.gitlab.statePath}/log/grpc.log - - - - /var/log/gitlab/grpc.log"
      "L+ ${config.services.gitlab.statePath}/log/production_json.log - - - - /var/log/gitlab/production_json.log"
      "f /var/log/gitlab/grpc.log 0750 ${config.services.gitlab.user} ${config.services.gitlab.group} -"
      "f /var/log/gitlab/production_json.log 0750 ${config.services.gitlab.user} ${config.services.gitlab.group} -"
    ];


    services.gitlab = {
      enable = true;
      databaseHost = "127.0.0.1";
      databaseCreateLocally = false;
      databasePasswordFile = "/srv/gitlab/secrets/db_password";
      initialRootPasswordFile = "/srv/gitlab/secrets/root_password";
      redisUrl = "redis://:${config.services.redis.requirePass}@localhost:6379/";
      statePath = "/srv/gitlab/state";
      https = true;
      port = 443;
      host = cfg.hostName;

      # less memory usage with jemalloc
      # ref https://brandonhilkert.com/blog/reducing-sidekiq-memory-usage-with-jemalloc/
      extraEnv.LD_PRELOAD = "${pkgs.jemalloc}/lib/libjemalloc.so";

      # all logs to /var/log
      extraShellConfig = {
        log_file = "/var/log/gitlab/gitlab-shell.log";
      };

      extraEnv.GITLAB_LOG_PATH = "/var/log/gitlab";
    };

    services.gitlab-runner = {
      enable = true;
      configFile = "/etc/gitlab-runner/config.toml";
    };

    services.logrotate.settings = {
      "/var/log/gitlab/*.log" = {
        copytruncate = true;
      };
    };

    services.nginx.commonHttpConfig = ''
      map $http_upgrade $connection_upgrade_gitlab {

          default upgrade;
          '''      close;
      }

      ## NGINX 'combined' log format with filtered query strings
      log_format gitlab_access $remote_addr_anon - $remote_user [$time_local] "$request_method $gitlab_filtered_request_uri $server_protocol" $status $body_bytes_sent "$gitlab_filtered_http_referer" "$http_user_agent";

      ## Remove private_token from the request URI
      # In:  /foo?private_token=unfiltered&authenticity_token=unfiltered&feed_token=unfiltered&...
      # Out: /foo?private_token=[FILTERED]&authenticity_token=unfiltered&feed_token=unfiltered&...
      map $request_uri $gitlab_temp_request_uri_1 {
        default $request_uri;
        ~(?i)^(?<start>.*)(?<temp>[\?&]private[\-_]token)=[^&]*(?<rest>.*)$ "$start$temp=[FILTERED]$rest";
      }

      ## Remove authenticity_token from the request URI
      # In:  /foo?private_token=[FILTERED]&authenticity_token=unfiltered&feed_token=unfiltered&...
      # Out: /foo?private_token=[FILTERED]&authenticity_token=[FILTERED]&feed_token=unfiltered&...
      map $gitlab_temp_request_uri_1 $gitlab_temp_request_uri_2 {
        default $gitlab_temp_request_uri_1;
        ~(?i)^(?<start>.*)(?<temp>[\?&]authenticity[\-_]token)=[^&]*(?<rest>.*)$ "$start$temp=[FILTERED]$rest";
      }

      ## Remove feed_token from the request URI
      # In:  /foo?private_token=[FILTERED]&authenticity_token=[FILTERED]&feed_token=unfiltered&...
      # Out: /foo?private_token=[FILTERED]&authenticity_token=[FILTERED]&feed_token=[FILTERED]&...
      map $gitlab_temp_request_uri_2 $gitlab_filtered_request_uri {
        default $gitlab_temp_request_uri_2;
        ~(?i)^(?<start>.*)(?<temp>[\?&]feed[\-_]token)=[^&]*(?<rest>.*)$ "$start$temp=[FILTERED]$rest";
      }

      ## A version of the referer without the query string
      map $http_referer $gitlab_filtered_http_referer {
        default $http_referer;
        ~^(?<temp>.*)\? $temp;
      }
    '';

    services.nginx.virtualHosts = {

      "${cfg.hostName}" = {
        enableACME = true;
        extraConfig = "access_log /var/log/nginx/gitlab_access.log gitlab_access;";
        forceSSL = true;
        locations = {
          "/" = {
            proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket";
            extraConfig = ''
              client_max_body_size 0;
              gzip off;

              ## https://github.com/gitlabhq/gitlabhq/issues/694
              ## Some requests take more than 30 seconds.
              proxy_read_timeout      300;
              proxy_connect_timeout   300;
              proxy_redirect          off;

              proxy_http_version 1.1;
              proxy_set_header    X-Real-IP           $remote_addr;
              proxy_set_header    X-Forwarded-For     $proxy_add_x_forwarded_for;
              proxy_set_header    X-Forwarded-Proto   $scheme;
              proxy_set_header    Upgrade             $http_upgrade;
              proxy_set_header    Connection          $connection_upgrade_gitlab;
            '';
          };

          "/assets/" = {
            alias = "${gitlabPackage}/share/gitlab/public/assets/";
          };

        };
      };

    };

    # Needed for Git via SSH.
    users.users.gitlab.extraGroups = [ "login" ];

  })

  (lib.mkIf (cfg.enable && cfg.enableDockerRegistry) {

    services.gitlab.registry = {
      enable = true;
      certFile = "/srv/gitlab/secrets/registry-auth.crt";
      keyFile = "/srv/gitlab/secrets/registry-auth.key";
      externalAddress = cfg.dockerHostName;
      externalPort = 443;
    };

    services.nginx.virtualHosts = {

      "${cfg.dockerHostName}" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:5000";
          extraConfig = ''
            client_max_body_size 2000M;
            proxy_read_timeout 900;
          '';
        };
      };
    };

  })

  (lib.mkIf cfg.manageSecrets {

    services.gitlab.secrets = {
      dbFile = "/srv/gitlab/secrets/db";
      secretFile = "/srv/gitlab/secrets/secret";
      otpFile = "/srv/gitlab/secrets/otp";
      jwsFile = "/srv/gitlab/secrets/jws";
    };

    # generate secrets on first start
    systemd.services.fc-gitlab-generate-secrets = {
      wantedBy = [ "gitlab.target" "multi-user.target" ];

      path = with pkgs; [ apg ];

      # not launching this with a condition, just in case we need more secrets in the future
      script = ''
        mkdir -p /srv/gitlab/secrets
        cd /srv/gitlab/secrets
        for x in db db_password jws otp root_password secret; do
          if [ ! -e "$x" ]; then
            apg -n1 -m40 > "$x"
          fi
        done
      '';
    };
  })

  ];
}
