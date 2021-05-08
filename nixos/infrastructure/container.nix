{ config, lib, ... }:

{
  config = lib.mkIf (config.flyingcircus.infrastructureModule == "container") {

    boot.isContainer = true;

    networking = {
      hostName = config.fclib.mkPlatform config.flyingcircus.enc.name;

      firewall.allowedTCPPorts = [ 80 ];
      firewall.allowPing = true;
    };

    flyingcircus.agent.enable = false;

    services.timesyncd.servers = [ "pool.ntp.org" ];
    services.telegraf.enable = false;

    systemd.services."network-addresses-ethsrv" = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        echo "Ready."
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    environment.sessionVariables = { NIX_REMOTE = "daemon"; };
    flyingcircus.agent.collect-garbage = lib.mkForce false;

    services.postgresql.settings.listen_addresses = lib.mkOverride 20 "0.0.0.0,::";
    services.postgresql.settings.fsync = "off";
    services.postgresql.settings.full_page_writes = "off";
    services.postgresql.settings.synchronous_commit = "off";

    services.mysql.extraOptions= ''
      [mysqld]
      # We don't really care about the data and this speeds up things.
      innodb_flush_method = nosync

      innodb_buffer_pool_size         = 200M
      innodb_log_buffer_size          = 64M
      innodb_file_per_table           = 1
      innodb_read_io_threads          = 1
      innodb_write_io_threads         = 1
      # Percentage. Probably needs local tuning depending on the workload.
      innodb_change_buffer_max_size   = 50
      innodb_doublewrite              = 1
      innodb_log_file_size            = 64M
      innodb_log_files_in_group       = 2
    '';

    services.redis.bind = lib.mkForce "0.0.0.0 ::";

    # This is the insecure key pair to allow bootstrapping containers.
    # -----BEGIN OPENSSH PRIVATE KEY-----
    # b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    # QyNTUxOQAAACBnO1dnNsxT0TJfP4Jgb9fzBJXRLiWrvIx44cftqs4mLAAAAJjYNRR+2DUU
    # fgAAAAtzc2gtZWQyNTUxOQAAACBnO1dnNsxT0TJfP4Jgb9fzBJXRLiWrvIx44cftqs4mLA
    # AAAEDKN3GvoFkLLQdFN+Blk3y/+HQ5rvt7/GALRAWofc/LFGc7V2c2zFPRMl8/gmBv1/ME
    # ldEuJau8jHjhx+2qziYsAAAAEHJvb3RAY3QtZGlyLWRldjIBAgMEBQ==
    # -----END OPENSSH PRIVATE KEY-----

    # ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGc7V2c2zFPRMl8/gmBv1/MEldEuJau8jHjhx+2qziYs root@ct-dir-dev2

    users.users.root.password = "";

    flyingcircus.users.userData = [
      { class = "human";
        gid = 100;
        home_directory = "/home/developer";
        id = 1000;
        login_shell = "/bin/bash";
        name = "Developer";
        # password: vagrant
        password = "$5$xS9kX8R5VNC0g$ZS7QkUYTk/61dUyUgq9r0jLAX1NbiScBT5v1PODz4UC";
        permissions = { container = [ "admins" "login" "manager" "sudo-srv" ]; };
        ssh_pubkey = [
         "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGc7V2c2zFPRMl8/gmBv1/MEldEuJau8jHjhx+2qziYs root@ct-dir-dev2"
        ];
        uid = "developer";}
      { class = "service";
        gid = 100;
        home_directory = "/srv/s-dev";
        id = 1001;
        login_shell = "/bin/bash";
        password = "*";
        name = "s-dev";
        ssh_pubkey = [] ;
        permissions = { container = []; };
        uid = "s-dev"; } ];

    flyingcircus.users.permissions = [
      { description = "commit to VCS repository";
        id = 2029;
        name = "code"; }
      { description = "perform interactive or web logins (e.g., ssh, monitoring)";
        id = 502;
        name = "login"; }
      { description = "access web statistics";
        id = 2046;
        name = "stats"; }
      { description = "sudo to service user";
        id = 2028;
        name = "sudo-srv"; }
      { description = "sudo to root";
        id = 10;
        name = "wheel"; }
      { description = "Manage users of RG";
        id = 2272;
        name = "manager"; } ];

    flyingcircus.users.adminsGroup = {
       gid = 2003; name = "admins"; technical_contacts = []; };

    users.users.developer = {
      # Make the human user a service user, too so that we can place stuff in
      # /etc/local/nixos for provisioning.
      extraGroups = [ "service" "login" ];
    };

    flyingcircus.passwordlessSudoRules = [
      { # Grant unrestricted access to developer
        commands = [ "ALL" ];
        users = [ "developer" ];
      }
    ];

    system.activationScripts.relaxHomePermissions = lib.stringAfter [ "users" ] ''
      mkdir -p /nix/var/nix/profiles/per-user/s-dev
      chown s-dev: /nix/var/nix/profiles/per-user/s-dev
    '';

  };
}
