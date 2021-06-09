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
    ];

    services.gitlab.extraShellConfig = {
      log_file = "/var/log/gitlab/gitlab-shell.log";
    };

    services.gitlab.extraEnv.GITLAB_LOG_PATH = "/var/log/gitlab";


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
