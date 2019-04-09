# Generic monitoring infrastructure and basic config option wire-up. For
# individual monitoring/telemetry services, see nixos/services/sensu.nix and
# nixos/services/telegraf.nix.  Monitoring *servers* are configured according to
# their respective roles.
{ config, pkgs, lib, ... }:

with lib;

let
  fclib = config.fclib;
  enc = config.flyingcircus.enc;
  params = if enc ? parameters then enc.parameters else {};
  labels = if enc ? labels then enc.labels else [];

  sensuServer = findFirst
    (s: s.service == "sensuserver-server")
    null
    config.flyingcircus.encServices;

  telegrafPort = "9126";

  encTags =
    listToAttrs
      (filter
        # Filter unwanted labels. Some are multi-valued, which does not make
        # sense for prometheus. The "env" might change, hence move metrics to
        # another time series. If the user creates custom labels this will
        # happen as well. But that's the user's choice then.
        (tag: ((tag.name != "fc_component") &&
               (tag.name != "fc_role") &&
               (tag.name != "env")))
        (map
          (split: nameValuePair (elemAt split 0) (elemAt split 1))
            (map (combined: splitString ":" combined) labels)));

  globalTags = encTags // optionalAttrs
    (params ? resource_group)
    { resource_group = params.resource_group; };

  telegrafInputs = {
    cpu = [{
      percpu = false;
      totalcpu = true;
    }];
    disk = [{
      mount_points = [
        "/"
        "/tmp"
      ];
    }];
    diskio = [{
      skip_serial_number = true;
    }];
    kernel = [{}];
    mem = [{}];
    netstat = [{}];
    net = [{}];
    processes = [{}];
    system = [{}];
    swap = [{}];
    socket_listener = [{
      service_address = "unix:///run/telegraf/influx.sock";
      data_format = "influx";
    }];
  };

in {
  config = mkMerge [

    (mkIf (sensuServer != null) {
      flyingcircus.services.sensu-client = {
        enable = true;
        server = sensuServer.address;
        password = sensuServer.password;
      };
    })

    (mkIf config.services.telegraf.enable {

      services.telegraf.extraConfig = {
        global_tags = globalTags;
        outputs = {
          prometheus_client = map
            (a: { listen = "${a}:${telegrafPort}"; })
            (fclib.listenAddressesQuotedV6 "ethsrv");
        };
        inputs = telegrafInputs;
      };

      flyingcircus.services.sensu-client.checks = {
        telegraf_prometheus_output = {
          notification = "Telegraf prometheus output alive";
          command =
            "check_http -v -j HEAD -H ${config.networking.hostName} " +
            "-p ${telegrafPort} -u /metrics";
        };
      };

      networking.firewall.extraCommands =
        "# FC telegraf\n" +
        (concatStringsSep ""
          (map (ip: ''
            ${fclib.iptables ip} -A nixos-fw -i ethsrv -s ${ip} \
              -p tcp --dport ${telegrafPort} -j nixos-fw-accept
          '')
          (fclib.listServiceIPs "statshostproxy-collector")));

    })

  ];
}
