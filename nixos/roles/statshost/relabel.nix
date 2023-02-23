# Relabeling rules that do not fit elsewhere.
# Role-specific rules should be put in the role definitions.

{ config, pkgs, lib, ... }:
with lib;
let
  renameMerge = options: [
    {
      source_labels = [ "__name__" ];
      # Only if there is no command set.
      regex = options.regex;
      replacement = "\${1}";
      target_label = options.targetLabel;
    }
    {
      source_labels = [ "__name__" ];
      regex = options.regex;
      replacement = options.targetName;
      target_label = "__name__";
    }
  ];

  removeLabel = prefix: label: {
    source_labels = [ "__name__" label ];
    regex = "${prefix}.*;.+";
    replacement = "";
    target_label = label;
  };
in
{
  flyingcircus.roles.statshost.prometheusMetricRelabel = [
    # This set is from the Graylog role has been removed with 22.11 but we
    # will have running instances for some time.
    {
      source_labels = [ "__name__" ];
      regex = "(org_graylog2)_(.*)$";
      replacement = "graylog_\${2}";
      target_label = "__name__";
    }
  ] ++ (renameMerge {
    regex = "netstat_tcp_(.*)";
    targetLabel = "state";
    targetName = "netstat_tcp";
  });
}
