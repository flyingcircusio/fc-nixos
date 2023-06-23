{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus.services.opensearch-dashboards;

  cfgFile = pkgs.writeText "opensearch-dashboards.json" (builtins.toJSON (
    (filterAttrsRecursive (n: v: v != null && v != []) ({
      server.host = cfg.listenAddress;
      server.port = cfg.port;
      server.ssl.certificate = cfg.cert;
      server.ssl.key = cfg.key;

      opensearchDashboards.index = cfg.index;
      opensearchDashboards.defaultAppId = cfg.defaultAppId;

      opensearch.hosts = cfg.opensearch.hosts;
      opensearch.username = cfg.opensearch.username;
      opensearch.password = cfg.opensearch.password;

      opensearch.ssl.certificate = cfg.opensearch.cert;
      opensearch.ssl.key = cfg.opensearch.key;
      opensearch.ssl.certificateAuthorities = cfg.opensearch.certificateAuthorities;
    } // cfg.extraConf)
  )));

in {
  options.flyingcircus.services.opensearch-dashboards = {
    enable = mkEnableOption "opensearch-dashboards service";

    listenAddress = mkOption {
      description = "opensearch-dashboards listening host";
      default = "127.0.0.1";
      type = types.str;
    };

    port = mkOption {
      description = "opensearch-dashboards listening port";
      default = 5601;
      type = types.int;
    };

    cert = mkOption {
      description = "opensearch-dashboards ssl certificate.";
      default = null;
      type = types.nullOr types.path;
    };

    key = mkOption {
      description = "opensearch-dashboards ssl key.";
      default = null;
      type = types.nullOr types.path;
    };

    index = mkOption {
      description = "opensearch index to use for saving kibana config.";
      default = ".opensearch_dashboards";
      type = types.str;
    };

    defaultAppId = mkOption {
      description = "opensearch default application id.";
      default = "discover";
      type = types.str;
    };

    opensearch = {

      hosts = mkOption {
        description = ''
          The URLs of the opensearch instances to use for all your queries.
          All nodes listed here must be on the same cluster.

          Defaults to <literal>[ "http://localhost:9200" ]</literal>.
        '';
        default = null;
        type = types.nullOr (types.listOf types.str);
      };

      username = mkOption {
        description = "Username for opensearch basic auth.";
        default = null;
        type = types.nullOr types.str;
      };

      password = mkOption {
        description = "Password for opensearch basic auth.";
        default = null;
        type = types.nullOr types.str;
      };

      ca = mkOption {
        description = ''
          CA file to auth against opensearch.
          It's recommended to use the <option>certificateAuthorities</option> option
          when using kibana-5.4 or newer.
        '';
        default = null;
        type = types.nullOr types.path;
      };

      certificateAuthorities = mkOption {
        description = ''
          CA files to auth against opensearch.

          Please use the <option>ca</option> option when using kibana &lt; 5.4
          because those old versions don't support setting multiple CA's.

          This defaults to the singleton list [ca] when the <option>ca</option> option is defined.
        '';
        default = if cfg.opensearch.ca == null then [] else [ca];
        type = types.listOf types.path;
      };

      cert = mkOption {
        description = "Certificate file to auth against opensearch.";
        default = null;
        type = types.nullOr types.path;
      };

      key = mkOption {
        description = "Key file to auth against opensearch.";
        default = null;
        type = types.nullOr types.path;
      };
    };

    package = mkOption {
      description = "opensearch-dashboards package to use";
      default = pkgs.opensearch-dashboards;
      defaultText = literalExpression "pkgs.opensearch-dashboards";
      type = types.package;
    };

    dataDir = mkOption {
      description = "opensearch-dashboards data directory";
      default = "/var/lib/opensearch-dashboards";
      type = types.path;
    };

    extraConf = mkOption {
      description = "opensearch-dashboards extra configuration";
      default = {};
      type = types.attrs;
    };
  };

  config = mkIf (cfg.enable) {
    systemd.services.opensearch-dashboards = {
      description = "opensearch-dashboards Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "elasticsearch.service" "opensearch.service" ];
      environment = { BABEL_CACHE_PATH = "${cfg.dataDir}/.babelcache.json"; };
      preStart = ''
        set -x
        pkg_dir=$STATE_DIRECTORY/package
        if [ -e $pkg_dir ]; then
            chmod -R u+w $pkg_dir
        fi
        rm -rf $pkg_dir
        cp -r ${cfg.package} $pkg_dir
        chmod -R u+w $pkg_dir
        rm -rf $pkg_dir/libexec/opensearch-dashboards/plugins/securityDashboards
        ls -a $pkg_dir/libexec/opensearch-dashboards/plugins
        sed -i "s|${cfg.package}|$pkg_dir|g" $pkg_dir/bin/opensearch-dashboards
      '';
      script = ''
        $STATE_DIRECTORY/package/bin/opensearch-dashboards \
          --config ${cfgFile} \
          --path.data ${cfg.dataDir}
      '';
      serviceConfig = {
        User = "opensearch-dashboards";
        WorkingDirectory = cfg.dataDir;
        StateDirectory = "opensearch-dashboards";
      };
    };

    environment.systemPackages = [ cfg.package ];

    users.users.opensearch-dashboards = {
      isSystemUser = true;
      description = "opensearch-dashboards service user";
      home = cfg.dataDir;
      createHome = true;
      group = "opensearch-dashboards";
    };
    users.groups.opensearch-dashboards = {};
  };
}
