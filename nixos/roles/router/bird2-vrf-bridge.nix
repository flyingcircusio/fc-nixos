{
  config,
  lib,
  pkgs,
  ...
}:

with builtins;

let
  inherit (config) fclib;
  inherit (config.flyingcircus) location;

  enableVrfBridge = any (net: net.linktype == "routed") (attrValues fclib.network);

  role = config.flyingcircus.roles.router;
  package = pkgs.bird2-vrf;

  # The set of networks on which we provide floating gateways in this
  # location is a good proxy for a list of networks whose routes we
  # should copy into VRF routing tables. On one hand, it accounts for
  # location-specific details like an access network, so that
  # e.g. hosts inside VRFs can reach Hydra. On the other hand, it also
  # provides reverse path routes pointing back to all the places we
  # otherwise have machines running which might want to reach services
  # hosted inside a VRF.
  sourceNetworks = role.floatingGatewayNetworks;
  sourceInterfaces = map (net: fclib.network."${net}".interface) sourceNetworks;

  configText = ''
    log stderr all;

    ipv4 table master4;
    ipv6 table master6;

    define RTPROT_BIRD = 12;
    define PRIMARY = ${if role.isPrimary then "true" else "false"};

    protocol device {
      scan time 60;
    }

  ''
  # As well as copying the default route from the main routing table,
  # we also copy over routes managed by the main Bird instance. This
  # handles routes learned from downstream networks, e.g. DEV from the
  # perspective of WHQ.
  + ''
    protocol kernel kernel_host_v4 {
      ipv4 {
        table master4;
        export none;
        import where net = 0.0.0.0/0 || krt_source = RTPROT_BIRD;
      };
      learn on;
    }
    protocol kernel kernel_host_v6 {
      ipv6 {
        table master6;
        export none;
        import where net = ::/0 || krt_source = RTPROT_BIRD;
      };
      learn on;
    }

    protocol direct iface_routes {
      ipv4 {
        table master4;
        export none;
        import all;
      };
      ipv6 {
        table master6;
        export none;
        import all;
      };

      interface ${lib.concatMapStringsSep ", " (name: "\"${name}\"") sourceInterfaces};
    }

  ''
  # Bird does not pick up routes pointing to VRF interfaces from the
  # kernel, so we need to teach it about them ourselves. This means
  # that if we terminate more than one VRF on a router then we
  # *should* automatically get inter-VRF routing.
  + (lib.concatMapStringsSep "\n" (net: ''
    ipv4 table tbl_${net.vrfInterface}_v4;
    ipv6 table tbl_${net.vrfInterface}_v6;

    protocol static static_${net.vrfInterface}_v4 {
      ipv4 {
        table master4;
        import all;
        export none;
      };
    ${lib.concatMapStringsSep "\n" (pfx: "  route ${pfx} via \"${net.vrfInterface}\";") net.v4.networks}
    }
    protocol static static_${net.vrfInterface}_v6 {
      ipv6 {
        table master6;
        import all;
        export none;
      };
    ${lib.concatMapStringsSep "\n" (pfx: "  route ${pfx} via \"${net.vrfInterface}\";") net.v6.networks}
    }

    protocol pipe pipe_${net.vrfInterface}_v4 {
      table tbl_${net.vrfInterface}_v4;
      peer table master4;
      import where PRIMARY && proto != "static_${net.vrfInterface}_v4";
      export none;
    }
    protocol pipe pipe_${net.vrfInterface}_v6 {
      table tbl_${net.vrfInterface}_v6;
      peer table master6;
      import where PRIMARY && proto != "static_${net.vrfInterface}_v6";
      export none;
    }

    protocol kernel ktable_${net.vrfInterface}_v4 {
      ipv4 {
        table tbl_${net.vrfInterface}_v4;
        import none;
        export all;
      };

      kernel table ${toString net.vrfTable};
    }
    protocol kernel ktable_${net.vrfInterface}_v6 {
      ipv6 {
        table tbl_${net.vrfInterface}_v6;
        import none;
        export all;
      };

      kernel table ${toString net.vrfTable};
    }

  '') (filter (n: n.linktype == "routed") (attrValues fclib.network)));

in
{
  config = lib.mkIf (role.enable && enableVrfBridge) {
    environment.systemPackages = [ package ];

    environment.etc."bird/bird-vrf.conf".source = pkgs.writeTextFile {
      name = "bird-vrf";
      text = configText;
      derivationArgs.nativeBuildInputs = [ package ];
      checkPhase = ''
        ln -s $out bird.conf
        vrf-bird -d -p -c bird.conf
      '';
    };

    environment.etc."iproute2/rt_protos.d/bird-vrf.conf".text = ''
      201 bird-vrf
    '';

    systemd.services.bird-vrf-bridge = {
      description = "BIRD Internet Routing Daemon (VRF Bridge)";
      wantedBy = [ "multi-user.target" ];
      reloadTriggers = [
        config.environment.etc."bird/bird-vrf.conf".source
      ];
      serviceConfig = {
        Type = "forking";
        Restart = "on-failure";
        User = "bird";
        Group = "bird";
        ExecStart = "${lib.getExe' package "vrf-bird"} -c /etc/bird/bird-vrf.conf";
        ExecReload = "${lib.getExe' package "vrf-birdc"} configure";
        ExecStop = "${lib.getExe' package "vrf-birdc"} down";
        RuntimeDirectory = "bird-vrf";
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_NET_BIND_SERVICE"
          "CAP_NET_RAW"
        ];
        AmbientCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_BIND_SERVICE"
          "CAP_NET_RAW"
        ];
        ProtectSystem = "full";
        ProtectHome = "yes";
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        PrivateTmp = true;
        PrivateDevices = true;
        SystemCallFilter = "~@cpu-emulation @debug @keyring @module @mount @obsolete @raw-io";
        MemoryDenyWriteExecute = "yes";
      };
    };
  };
}
