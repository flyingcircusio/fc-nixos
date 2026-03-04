{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.flyingcircus.roles.tempo;
  fclib = config.fclib;

  prometheus_host =
    let
      # TODO service an der rolle im directory hinterlegen
      prometheus_server = fclib.findOneService "statshost-master-collector";
    in
    lib.replaceStrings [ "gocept.net" ] [ "fcio.net" ] prometheus_server.address;
  prometheus_port = 9090;
in
{
  options = with lib; {
    flyingcircus.roles.tempo = {
      enable = mkEnableOption "Flying Circus Grafana Tempo server";
      supportsContainers = fclib.mkEnableDevhostSupport;

      s3 = mkOption {
        description = "Configure trace storage in S3-compatible object store";
        default = { };
        type = types.submodule {
          options = {
            enable = mkEnableOption "storing traces in object storage" // {
              default = config.flyingcircus.enc ? role_configuration.tempo;
            };
            endpoint = mkOption {
              type = types.str;
              description = "HTTP(S) endpoint of the object store";
              default = "rgw.local:7480";
              defaultText = "<local rgw address>";
            };
            bucketName = fclib.mkRoleOption "tempo" {
              description = "object storage bucket name";
              type = types.str;
              default = c: c.object_store_bucket;
            };
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.tempo = {
          enable = true;
          settings = {
            stream_over_http_enabled = true;
            server.grpc_listen_port = 9096;
            ingester = {
              lifecycler.ring.replication_factor = 1;
              trace_idle_period = "10s";
            };
            query_frontend = { };
            querier = { };
            metrics_generator = {
              registry.external_labels = {
                source = "tempo";
                cluster = "";
              };
              storage = {
                path = "/var/tempo/generator/wal";
                remote_write = [
                  {
                    url = "http://${prometheus_host}:${toString prometheus_port}/api/v1/write";
                    send_exemplars = true;
                  }
                ];
              };
              traces_storage.path = "/var/tempo/generator/traces";
              processor = {
                local_blocks = {
                  filter_server_spans = false;
                  flush_to_storage = true;
                };
              };
            };
            distributor.receivers.otlp = {
              protocols =
                let
                  v4 = builtins.head config.fclib.network.srv.v4.addresses;
                in
                {
                  grpc.endpoint = "${v4}:4317";
                  http.endpoint = "${v4}:4318";
                };
            };
          };
        };

        systemd.tmpfiles.rules = [
          "L+ /var/tempo   -    -    -     -  /var/lib/tempo"
        ];
      }

      (lib.mkIf cfg.s3.enable (
        let
          credentialFile = "/run/tempo/s3-env";
        in
        {
          services.tempo.settings = {
            storage.trace = {
              backend = "s3";
              s3 = {
                bucket = cfg.s3.bucketName;
                endpoint = cfg.s3.endpoint;
                forcepathstyle = true;
                insecure = true;
              };
            };
          };

          users.groups.tempoenv = { };

          systemd.tmpfiles.rules = [
            "d '/run/tempo' 0750 root tempoenv - -"
            "Z '/run/tempo' 0750 root tempoenv - -"
          ];

          systemd.services.tempo = {
            serviceConfig.SupplementaryGroups = [ "tempoenv" ];
            serviceConfig.EnvironmentFile = [ credentialFile ];
          };

          systemd.services.tempo-s3-setup = {
            wantedBy = [ "tempo.service" ];
            before = [ "tempo.service" ];

            script = ''
              if [ -z $AWS_ACCESS_KEY_ID ]; then
                AWS_ACCESS_KEY_ID=$(cat ${config.flyingcircus.encPath} | ${lib.getExe pkgs.jq} '.role_configuration.tempo.object_store_access_key')
              fi
              if [ -z $AWS_SECRET_ACCESS_KEY ]; then
                AWS_SECRET_ACCESS_KEY=$(cat ${config.flyingcircus.encPath} | ${lib.getExe pkgs.jq} '.role_configuration.tempo.object_store_secret_key')
              fi

              export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
              ${pkgs.awscli2}/bin/aws s3 --endpoint-url http://${cfg.s3.endpoint} mb s3://${cfg.s3.bucketName} --region ""

              mkdir -p $(dirname ${credentialFile});
              cat >${credentialFile} <<EOF
              AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
              AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
              EOF

              chown :tempoenv ${credentialFile}
            '';

            serviceConfig = {
              Type = "oneshot";
              User = "root";
            };
          };
        }
      ))
    ]
  );
}
