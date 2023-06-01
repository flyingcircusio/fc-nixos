{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus.roles.devhost;

  vmOptions = {
    options = {
      memory = mkOption {
        description = "Memory assigned to the VM";
        type = types.str;
        example = "1024M";
      };
      cores = mkOption {
        description = "CPU cores assigned to the VM";
        type = types.int;
        example = 2;
      };
      aliases = mkOption {
        description = "Aliases set in the nginx proxy, forwarding to the VM";
        type = types.listOf types.str;
        default = [];
      };
    };
  };

  addColons = text: lib.concatStringsSep ":" (lib.genList (x: lib.substring (x * 2) 2 text) ((lib.stringLength text) / 2));
  convertNameToMAC = name: vlanId: "02:${vlanId}:" + (addColons (lib.substring 0 8 (builtins.hashString "md5" name)));

  ifaceUpScript = pkgs.writeShellScript "fc-devhost-vm-iface-up" ''
    ${pkgs.iproute2}/bin/ip tuntap add name $1 mode tap
    ${pkgs.iproute2}/bin/ip link set $1 up
    sleep 0.2s
    ${pkgs.iproute2}/bin/ip link set $1 master br-vm-srv
  '';
  ifaceDownScript = pkgs.writeShellScript "fc-devhost-vm-iface-down" ''
    sleep 0.2s
    ${pkgs.iproute2}/bin/ip tuntap del name $1 mode tap
  '';

  defaultService = {
    description = "FC dev Virtual Machine '%i'";
    path = [ pkgs.qemu_kvm ];
    serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";
  };
  mkService = name: vmCfg: nameValuePair "fc-devhost-vm@${name}" (recursiveUpdate defaultService {
    enable = true;
    wantedBy = [ "machines.target" ];

    serviceConfig.ExecStart = (escapeShellArgs
      [
        "${pkgs.qemu_kvm}/bin/qemu-system-x86_64"
        "-name" name
        "-enable-kvm"
        "-smp" vmCfg.cores
        "-m" vmCfg.memory
        "-nodefaults"
        "-no-user-config"
        "-no-reboot"
        "-nographic"
        "-drive" "id=root,format=qcow2,file=/var/lib/devhost/vms/${name}/rootfs.qcow2,if=virtio,aio=threads"
        "-netdev" "tap,id=ethsrv-${name},ifname=vm-srv-${name},script=${ifaceUpScript},downscript=${ifaceDownScript}"
        "-device" "virtio-net,netdev=ethsrv-${name},mac=${convertNameToMAC name "03"}"
        "-serial" "file:/var/lib/devhost/vms/${name}/log"
      ]);
  });

  manage_script = pkgs.writeShellScriptBin "fc-manage-dev-vms" ''
    #!/bin/bash
    set -ex

    # Named optional arguments m (memory) and c (cores)
    memory="512M"
    cores=2
    while getopts ":m:c:" opt; do
      case $opt in
        m) memory="$OPTARG"
        ;;
        c) cores="$OPTARG"
        ;;
        \?) echo "Invalid option -$OPTARG" >&2
        exit 1
        ;;
      esac
    done
    shift $((OPTIND-1))

    action=''${1?need to specify action}

    manage_alias_proxy=${lib.boolToString cfg.enableAliasProxy}

    mkdir -p /etc/devhost/vm-configs
    if [[ ! -f "/var/lib/devhost/ssh_bootstrap_key" ]]; then
       cat > /var/lib/devhost/ssh_bootstrap_key <<EOF
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBnO1dnNsxT0TJfP4Jgb9fzBJXRLiWrvIx44cftqs4mLAAAAJjYNRR+2DUU
fgAAAAtzc2gtZWQyNTUxOQAAACBnO1dnNsxT0TJfP4Jgb9fzBJXRLiWrvIx44cftqs4mLA
AAAEDKN3GvoFkLLQdFN+Blk3y/+HQ5rvt7/GALRAWofc/LFGc7V2c2zFPRMl8/gmBv1/ME
ldEuJau8jHjhx+2qziYsAAAAEHJvb3RAY3QtZGlyLWRldjIBAgMEBQ==
-----END OPENSSH PRIVATE KEY-----
EOF
    chmod 600 /var/lib/devhost/ssh_bootstrap_key
    fi

    case "$action" in
      help)
        echo "usage: fc-manage-dev-vms [options] ACTION VM_NAME [HYDRA_EVAL]

Options:
-m           Memory of the VM. Format: Number + Unit in 1 Letter. Example: 1024M
-c           CPU Cores of the VM. Format: Number

Arguments:
ACTION       must be one of help, destroy, ensure
VM_NAME      the name of the vm to be created or destroyed
HYDRA_EVAL   ID of the FC NixOS Hydra evaluation. Used for determining channel and base image of the VM. Required when ACTION=ensure
"
;;
      destroy)
        vm=''${2?need to specify vm name}
        rm /etc/devhost/vm-configs/$vm.nix
        rm -r /var/lib/devhost/vms/$vm || true
        fc-manage -v -b
      ;;
      ensure)
        vm=''${2?need to specify vm name}
        eval_id=''${3?need to specify Flying Circus Hydra eval id}
        aliases=''${4}
        aliases=$(echo $aliases | sed 's| |" "|g;s|.*|"&"|')
        channel_url="https://hydra.flyingcircus.io/build/$(curl -H "Accept: application/json" -L https://hydra.flyingcircus.io/eval/$eval_id/job/release | jq -r .id)/download/1/nixexprs.tar.xz"
        channel_path=''${channel_url#file://}

        vm_exists=false
        if [[ -f "/etc/devhost/vm-configs/$vm.nix" ]]; then
          vm_exists=true
        fi
        mkdir -p /var/lib/devhost/vms/$vm
        cat > /etc/devhost/vm-configs/$vm.nix <<EOF
## DO NOT TOUCH!
## Managed by fc-manage-dev-vms
{ ... }: {
  flyingcircus.roles.devhost.virtualMachines = {
    "$vm" = {
      memory = "$memory";
      cores = $cores;
    };
  };
}

EOF
        if [ "$vm_exists" = false ]; then
          vm_base_image_store_path=$(curl -H "Accept: application/json" -L https://hydra.flyingcircus.io/eval/$eval_id/job/images.dev-vm | jq -r ".buildproducts[] | select(.subtype==\"img\").path")
          nix-store -r $vm_base_image_store_path
          cp $vm_base_image_store_path /var/lib/devhost/vms/$vm/rootfs.qcow2
          fc-manage -v -b
          until ping -qc 1 dev-vm
          do
            sleep 0.5s
          done
          jq -n --arg channel_url "$channel_url" '{parameters: {environment_url: $channel_url, environment: "dev-vm"}}' > /tmp/devhost-vm-enc.json
          rsync -e "ssh -o StrictHostKeyChecking=no -i /var/lib/devhost/ssh_bootstrap_key" --rsync-path="sudo rsync" /tmp/devhost-vm-enc.json developer@dev-vm:/etc/nixos/enc.json
          rm /tmp/devhost-vm-enc.json
          cat > /tmp/devhost-vm-name.nix <<EOF
{ ... }: {
  flyingcircus.enc = { name = "$vm"; };
}
EOF
          rsync -e "ssh -o StrictHostKeyChecking=no -i /var/lib/devhost/ssh_bootstrap_key" --rsync-path="sudo rsync" /tmp/devhost-vm-name.nix developer@dev-vm:/etc/local/nixos/vm-name.nix
          rm /tmp/devhost-vm-name.nix
          ssh -o "StrictHostKeyChecking=no" -i /var/lib/devhost/ssh_bootstrap_key developer@dev-vm "sudo fc-manage -v -c && sudo systemctl restart dhcpcd"
        else
          jq -n --arg channel_url "$channel_url" '{parameters: {environment_url: $channel_url, environment: "dev-vm"}}' > /tmp/devhost-vm-enc.json
          rsync -e "ssh -o StrictHostKeyChecking=no -i /var/lib/devhost/ssh_bootstrap_key" --rsync-path="sudo rsync" /tmp/devhost-vm-enc.json developer@$vm:/etc/nixos/enc.json
        fi
        # This is needed because otherwise nginx fails to start, because the host hasn't got it's correct hostname yet
        cat > /etc/devhost/vm-configs/$vm.nix <<EOF
## DO NOT TOUCH!
## Managed by fc-manage-dev-vms
{ ... }: {
  flyingcircus.roles.devhost.virtualMachines = {
    "$vm" = {
      memory = "$memory";
      cores = $cores;
      aliases = [ $aliases ];
    };
  };
}

EOF
      fc-manage -v -b
    esac
  '';
in {
  options = {
    flyingcircus.roles.devhost = {
      virtualMachines = mkOption {
        description = ''
          Description of devhost virtual machines. This config will be auto-generated by batou.
          Only of relevance when `flyingcircus.roles.devhost.virtualisationType = "vm"`.
        '';
        type = types.attrsOf (types.submodule vmOptions);
        default = {};
      };
    };
  };
  config = lib.mkIf (cfg.enable && cfg.virtualisationType == "vm") {
    environment.systemPackages = [ manage_script ];
    security.sudo.extraRules = lib.mkAfter [{
      commands = [{
        command = "${manage_script}/bin/fc-manage-dev-vms";
        options = [ "NOPASSWD" ];
      }];
      groups = [ "service" "users" ];
    }];
    # FIXME: Align network interface names with production
    networking = {
      bridges."br-vm-srv" = {
        interfaces = [];
      };
      interfaces = {
        "br-vm-srv" = {
          ipv4.addresses = [
            { address = "10.12.0.1"; prefixLength = 20; }
          ];
        };
      };
      nat = {
        enable = true;
        enableIPv6 = true;
        internalInterfaces = [ "br-vm-srv" ];
      };
    };
    services.dnsmasq = {
      enable = true;
      # FIXME: Either use the hosts dnsmasq or the correct rz nameservers
      extraConfig = ''
        interface=br-vm-srv

        dhcp-range=10.12.0.10,10.12.12.254,255.255.240.0,24h
        dhcp-option=option:router,10.12.0.1
        dhcp-option=6,8.8.8.8
      '';
    };
    networking.firewall.interfaces."br-vm-srv".allowedUDPPorts = [ 67 ];
    networking.firewall.interfaces."vm-srv+".allowedUDPPorts = [ 67 ];
    systemd.services = {
      "fc-devhost-vm@" = defaultService;
    } // mapAttrs' mkService cfg.virtualMachines;

    services.nginx.virtualHosts = if cfg.enableAliasProxy then
      (let
        suffix = cfg.publicAddress;
        vms =
          filterAttrs (name: vmCfg: vmCfg.aliases != [ ]) cfg.virtualMachines;
        generateVhost = vmName: vmCfg: nameValuePair "${vmName}.${suffix}" {
          serverAliases = map (alias: "${alias}.${vmName}.${suffix}") vmCfg.aliases;
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "https://${vmName}";
          };
        };
      in (mapAttrs' generateVhost vms))
    else
      { };
  };
}
