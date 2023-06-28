{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  enc = config.flyingcircus.enc;
  secrets = enc.parameters.secrets;
  public_address = head fclib.network.fe.v6.addressesQuoted;
  public_fqdn = "${enc.name}.fe.${enc.parameters.location}.fcio.net";
  server_secret_script = fclib.python3BinFromFile ./update-server-secrets.py;
in
{
  options = {
    flyingcircus.roles.consul_server = {
      enable = lib.mkEnableOption "Enable Consul server role";
      supportsContainers = fclib.mkDisableContainerSupport;
    };
  };

  config = lib.mkIf config.flyingcircus.roles.consul_server.enable {

    flyingcircus.services.consul.enable = true;

    services.consul.webUi = true;

    services.consul.extraConfig = {
        server = true;
        bootstrap_expect = 3;
    };

    systemd.services.consul.restartTriggers = [
        (builtins.hashString "sha256" secrets."consul/master_token")
        (builtins.hashString "sha256" secrets."consul/agent_token")
        server_secret_script
      ];

    flyingcircus.activationScripts.consul-update-server-secrets = ''
      ${server_secret_script}/bin/update-server-secrets
    '';

    # Public interface
    networking.firewall.allowedTCPPorts = [ 8500 ];

    # Internal interface
    networking.firewall.extraCommands = ''
      ip6tables -A nixos-fw -i ${fclib.network.srv.device} -p tcp --dport 8301 -j nixos-fw-accept
      ip6tables -A nixos-fw -i ${fclib.network.srv.device} -p tcp --dport 8300 -j nixos-fw-accept
    '';

    flyingcircus.services.nginx.enable = true;

    services.nginx = {
      virtualHosts."${public_fqdn}" = {
        listen = [ { addr = public_address; port = 8500; ssl = true;}
                   # allow acme and the certificate checks to work
                   { addr = public_address; port = 80; ssl = false;}
                   { addr = public_address; port = 443; ssl = true;} ];
        enableACME = true;
        addSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:8500";
          extraConfig = ''
            # Workaround for nginx bug
            # https://yt.flyingcircus.io/issue/PL-130533
            #
            keepalive_requests 0;
            # Consul server access
          '' + (lib.concatMapStrings (net: ''
            allow ${net};
          '') fclib.networks.all) + ''
            deny all;
          '';
        };

      };
    };

  };


}
