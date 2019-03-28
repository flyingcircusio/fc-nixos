    flyingcircus.roles.statshost.prometheusMetricRelabel =
      let
        rename_merge = options:
          [
            {
              source_labels = [ "__name__" ];
              # Only if there is no command set.
              regex = options.regex;
              replacement = "\${1}";
              target_label = options.target_label;
            }
            {
              source_labels = [ "__name__" ];
              regex = options.regex;
              replacement = options.target_name;
              target_label = "__name__";
            }
          ];
      in (
        (rename_merge {
          regex = "netstat_tcp_(.*)";
          target_label = "state";
          target_name = "netstat_tcp";
         })

      );

