{
  config,
  lib,
  pkgs,
  ...
}:

# Our management agent keeping the system up to date, configuring it based on
# changes to our nixpkgs clone and data from our directory

with builtins;

let
  cfg = config.flyingcircus.agent;
  fclib = config.fclib;
  stampFile = "/var/lib/fc-collect-garbage/last_run.stamp";

in
{
  options = with lib; {
    flyingcircus.agent = {
      collect-garbage = mkEnableOption "automatic scanning for Nix store references and garbage collection";
      userscan-exclude-patterns = lib.mkOption {
        default = [ ];
        type = types.listOf types.str;
        description = "Patterns to ignore while scanning for store references.";
      };
      userscan-ignore-users = lib.mkOption {
        default = [ ];
        type = types.listOf types.str;
        description = "Users to ignore while scanning for store references.";
      };
    };
  };

  config = lib.mkMerge [
    {
      flyingcircus.agent.userscan-exclude-patterns = [
        # Directories to ignore (anywhere in the home directory)
        "**/.git/objects/"
        "**/.gnupg/"
        "**/.hg/store/"
        "**/.nix-defexpr/"
        "**/elasticsearch/data/"
        "**/graylog/data/"
        "**/influxdb/data/"
        "**/journal/"
        "**/lucene/"
        "**/solr/data/"
        # Very big, has misleading store paths which shouldn't be registered.
        "**/nixpkgs*/"
        # If we missed a nixpkgs directory: test files from this directory trip
        # userscan over as they contain store paths which are too long on purpose.
        "**/pkgs/test/make-binary-wrapper/*"
        # Files in sub-directories to ignore (anywhere in the home directory)
        "**/.local/share/fish/fish_history"
        "**/diagnostic.data/metrics.*"
        "**/mongodb/*.wt"
        "**/mysql/*/*.{MYD,MYI,frm,ibd}"
        "**/mysql/ib*"
        "**/postgresql/*/base"
        "**/postgresql/*/pg_*"
        "**/redis/*.rdb"
        # File extensions to ignore
        "*.JPG"
        "*.bak"
        "*.bmp"
        "*.bz2"
        "*.crt"
        "*.css"
        "*.deb"
        "*.diff"
        "*.doc"
        "*.docx"
        "*.eml"
        "*.flac"
        "*.gif"
        "*.gz"
        "*.htm"
        "*.html"
        "*.icc"
        "*.jar"
        "*.jpeg"
        "*.jpg"
        "*.json"
        "*.kml"
        "*.kmz"
        "*.lock"
        "*.log"
        "*.log-????????"
        "*.log.?"
        "*.lzh"
        "*.m4a"
        "*.md"
        "*.mid"
        "*.mp3"
        "*.mp4"
        "*.ods"
        "*.odt"
        "*.ogg"
        "*.otf"
        "*.patch"
        "*.pcl"
        "*.pdf"
        "*.pdf"
        "*.pid"
        "*.pki"
        "*.png"
        "*.ppt"
        "*.pptx"
        "*.psd"
        "*.psd"
        "*.rar"
        "*.rpm"
        "*.rss"
        "*.sock"
        "*.socket"
        "*.spl"
        "*.sql"
        "*.svg"
        "*.tgz"
        "*.tif"
        "*.tiff"
        "*.ttf"
        "*.vcl"
        "*.war"
        "*.wav"
        "*.webm"
        "*.xlf"
        "*.xls"
        "*.xlsx"
        "*.xml"
        "*.xz"
        "*.zdsock"
        "*.zopectlsock"
        "*~"
        # Cache, history and data files to ignore
        ".bash_history"
        ".viminfo"
        ".z"
        ".zsh_history"
        "Data.fs"
        "Data.fs.tmp"
        "GeoLite2-City.mmdb"
        "fc-userscan.cache"
        "zeoclient_*.zec"
      ];

      environment.etc."fc-userscan/exclude-patterns".text =
        lib.concatStringsSep "\n" cfg.userscan-exclude-patterns;
      environment.etc."fc-userscan/ignore-users".text =
        lib.concatStringsSep "\n" cfg.userscan-ignore-users;

      systemd.tmpfiles.rules = [
        "d /var/log/fc-collect-garbage - - - 30d"
        # Obsolete stamp file location, it's now in /var/lib/fc-collect-garbage
        "r /var/log/fc-collect-garbage.log"
      ];
    }

    (lib.mkIf cfg.collect-garbage {

      flyingcircus.services.sensu-client = {
        checks.fc-collect-garbage = {
          notification = "nix-collect-garbage stamp recent";
          command = "${pkgs.monitoring-plugins}/bin/check_file_age" + " -f ${stampFile} -w 216000 -c 432000";
        };
      };

      systemd.services.fc-collect-garbage = {
        description = "Scan users for Nix store references and collect garbage";
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          # Use the lowest priority settings we can findto make sure that GC
          # gives way to nearly everything else.
          CPUSchedulingPolicy = "idle";
          CPUWeight = 1;
          IOSchedulingClass = "idle";
          IOSchedulingPriority = 7;
          IOWeight = 1;
          Nice = 19;
          StateDirectory = "fc-collect-garbage";
          # We expect our script to produce error codes from 0 to 3.
          # Ignore them as they are often temporary and the garbage collection
          # runs every day. There's a Sensu check that warns us when garbage collection
          # doesn't work for longer time periods.
          SuccessExitStatus = [
            1
            2
            3
          ];
          TimeoutStartSec = "infinity";
        };
        path = with pkgs; [
          fc.userscan
          glibc
          util-linux
        ];
        environment = {
          LANG = "en_US.utf8";
          PYTHONUNBUFFERED = "1";
        };
        script = ''
          ${cfg.package}/bin/fc-collect-garbage \
            --verbose \
            --stamp-file ${stampFile}
        '';
      };

      systemd.timers.fc-collect-garbage = {
        description = "Timer for fc-collect-garbage";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "00:00:00";
          RandomizedDelaySec = "24h";
        };
      };

    })
  ];
}
