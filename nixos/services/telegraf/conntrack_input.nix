{ pkgs, ... }:
{
  flyingcircus.services.telegraf.inputs = {
    conntrack = [{
      files = [ "nf_conntrack_count" "nf_conntrack_max" ];
      dirs = [ "/proc/sys/net/netfilter" ];
    }];
  };
}
