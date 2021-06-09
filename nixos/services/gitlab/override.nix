{ config, lib, pkgs, utils, ... }:

with lib;
let
  cfg = config.services.gitlab;
in
{
  config = {
    # all logs to /var/log
    systemd.tmpfiles.rules = [
      "d /var/log/gitlab 0750 ${cfg.user} ${cfg.group} -"
      "L+ ${cfg.statePath}/log/grpc.log - - - - /var/log/gitlab/grpc.log"
      "L+ ${cfg.statePath}/log/production_json.log - - - - /var/log/gitlab/production_json.log"
      "f /var/log/gitlab/grpc.log 0750 ${cfg.user} ${cfg.group} -"
      "f /var/log/gitlab/production_json.log 0750 ${cfg.user} ${cfg.group} -"
    ];

    services.gitlab.extraShellConfig = {
      log_file = "/var/log/gitlab/gitlab-shell.log";
    };

    services.gitlab.extraEnv.GITLAB_LOG_PATH = "/var/log/gitlab";

    # less memory usage with jemalloc
    # ref https://brandonhilkert.com/blog/reducing-sidekiq-memory-usage-with-jemalloc/
    services.gitlab.extraEnv.LD_PRELOAD = "${pkgs.jemalloc}/lib/libjemalloc.so";

    # generate secrets on first start
    systemd.services.gitlab-generate-secrets = {
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
  };

}
