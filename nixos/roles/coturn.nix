{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  listenAddresses =
    fclib.listenAddresses "lo" ++
    fclib.listenAddresses "ethsrv" ++
    fclib.listenAddresses "ethfe";

  serviceCfg = config.services.coturn;
  localDir = config.flyingcircus.localConfigDirs.coturn.dir;

  coturnShowConfig = pkgs.writeScriptBin "coturn-show-config" ''
    cat $(systemctl cat coturn.service | grep "ExecStart" | cut -d" " -f3)
  '';

  domain = config.networking.domain;
  location = lib.attrByPath [ "parameters" "location" ] "standalone" config.flyingcircus.enc;
  feFQDN = "${config.networking.hostName}.fe.${location}.${domain}";
  cfg = config.flyingcircus.roles.coturn;

  ourSettings = [
    "extraConfig"
    "hostname"
    ];

  defaultConfig = {
    hostname = feFQDN;
    alt-listening-port = 3479;
    alt-tls-listening-port = 5350;
    listening-ips = listenAddresses;
    listening-port = 3478;
    lt-cred-mech = false;
    no-cli = true;
    realm = feFQDN;
    tls-listening-port = 5349;
    use-auth-secret = true;
    extraConfig = [];
  };

  jsonConfig = fromJSON
    (fclib.configFromFile /etc/local/coturn/config.json "{}");


  hostname = jsonConfig.hostname or defaultConfig.hostname;
  kill = "${pkgs.coreutils}/bin/kill";
in
{
  options = with lib; {
    flyingcircus.roles.coturn = {
      enable = lib.mkEnableOption "Coturn TURN server";
    };
  };

  config = lib.mkIf cfg.enable {
    services.coturn = {
      enable = true;
      cert = "/var/lib/acme/${hostname}/fullchain.pem";
      pkey = "/var/lib/acme/${hostname}/key.pem";
      extraConfig = lib.concatStringsSep "\n" jsonConfig.extraConfig or [];
    } // (mapAttrs (name: value: lib.mkDefault value) (removeAttrs defaultConfig ourSettings))
      // (removeAttrs jsonConfig ourSettings);

    networking.firewall.allowedTCPPorts = [ 80 ];

    # We need this only for the Letsencrypt HTTP challenge.
    services.nginx = {
      enable = true;
      virtualHosts."${hostname}" = {
        enableACME = true;
      };
    };

    systemd.services.coturn = rec {
      requires = [ "acme-selfsigned-${hostname}.service" ];
      after = requires;
      serviceConfig = {
        Restart = lib.mkForce "always";
      };
    };

    security.acme.certs."${hostname}" = {
      allowKeysForGroup = true;
      user = lib.mkForce "root";
      group = "turnserver";
      postRun = "systemctl kill -s USR2 coturn.service";
    };

    flyingcircus.services = {
      sensu-client.checks = {

        coturn = {
          notification = "coturn not reachable via TCP";
          command = ''
            ${pkgs.sensu-plugins-network-checks}/bin/check-ports.rb \
              -h ${lib.concatStringsSep "," serviceCfg.listening-ips} \
              -p ${toString serviceCfg.tls-listening-port}
          '';
        };

      };
    };

    flyingcircus.localConfigDirs.coturn = {
      dir = "/etc/local/coturn";
      user = "turnserver";
    };

    environment.systemPackages = [
      coturnShowConfig
    ];

    environment.etc."local/coturn/README.txt".text = ''
    Coturn (Turnserver)
    -------------------

    Put your config in ${localDir}/config.json.
    Default settings are shown in ${localDir}/config.json.example.
    Options defined in config.json override these.

    The JSON config supports all options defined by NixOS:

    https://nixos.org/nixos/options.html#coturn

    In addition to that, hostname must be set for the Letsencrypt SSL cert.
    Unsupported options can be added to extraConfig which is a list of strings
    that are put as lines at the end of the configuration file.

    The default config sets use-auth-secret but no secret.
    You have to add static-auth-secret to config.json.

    By default, coturn listens on all interfaces but ports are firewalled.
    Add custom rules to /etc/local/firewall if you want public access.
    '';

    environment.etc."local/coturn/config.json.example".source =
      fclib.writePrettyJSON "config.json.example" defaultConfig;
  };
}
