{ lib, ... }:
with lib; with types; let

globalOptions = {
  daemon = mkOption {
    default = true;
    type = bool;
    description = ''
      # `daemon`
      Makes the process fork into background. This is the recommended mode of
      operation. It is equivalent to the command line "-D" argument. It can be
      disabled by the command line "-db" argument. This option is ignored in
      systemd mode.

      From HAProxy Documentation
    '';
    example = false;
  };
  chroot = mkOption {
    default = "/var/empty";
    type = str;
    description = ''
      # `chroot <jail dir>`
      Changes current directory to <jail dir> and performs a chroot() there before
      dropping privileges. This increases the security level in case an unknown
      vulnerability would be exploited, since it would make it very hard for the
      attacker to exploit the system. This only works when the process is started
      with superuser privileges. It is important to ensure that <jail_dir> is both
      empty and non-writable to anyone.

      From HAProxy Documentation
    '';
    example = "/var/lib/haproxy";
  };
  user = mkOption {
    default = "haproxy";
    type = str;
    description = ''
      # `user <user name>`
      Changes the process's user ID to UID of user name <user name> from /etc/passwd.
      It is recommended that the user ID is dedicated to HAProxy or to a small set
      of similar daemons. HAProxy must be started with superuser privileges in order
      to be able to switch to another one.

      From HAProxy Documentation
    '';
    example = "hapuser";
  };
  group = mkOption {
    default = "haproxy";
    type = str;
    description = ''
      # `group <group name>`
      Changes the process's group ID to the GID of group name <group name> from
      /etc/group. It is recommended that the group ID is dedicated to HAProxy
      or to a small set of similar daemons. HAProxy must be started with a user
      belonging to this group, or with superuser privileges. Note that if haproxy
      is started from a user having supplementary groups, it will only be able to
      drop these groups if started with superuser privileges.

      From HAProxy Documentation
    '';
  };
  maxconn = mkOption {
    default = 4096;
    type = int;
    description = ''
      # `maxconn <number>`
      Sets the maximum per-process number of concurrent connections to <number>. It
      is equivalent to the command-line argument "-n". Proxies will stop accepting
      connections when this limit is reached. The "ulimit-n" parameter is
      automatically adjusted according to this value. See also "ulimit-n". Note:
      the "select" poller cannot reliably use more than 1024 file descriptors on
      some platforms. If your platform only supports select and reports "select
      FAILED" on startup, you need to reduce maxconn until it works (slightly
      below 500 in general). If this value is not set, it will automatically be
      calculated based on the current file descriptors limit reported by the
      "ulimit -n" command, possibly reduced to a lower value if a memory limit
      is enforced, based on the buffer size, memory allocated to compression, SSL
      cache size, and use or not of SSL and the associated maxsslconn (which can
      also be automatic).

      From HAProxy Documentation
    '';
  };
  extraConfig = mkOption {
    default = ''
      log localhost local2
      # Increase buffers for large URLs
      tune.bufsize 131072
      tune.maxrewrite 65536
    '';
    type = lines;
    description = ''
      Additional text appended to global section of haproxy config.
    '';
  };
};

defaultsOptions = {
  mode = modeOption // {
    default = "http";
  };
  options = optionsOption // {
    default = [
      "httplog"
      "dontlognull"
      "http-server-close"
    ];
  };
  timeout = timeoutOption // {
    default = {
      connect = "5s";
      client = "30s";
      server = "30s";
      queue = "25s";
    };
  };
  balance = balanceOption;
  extraConfig = mkOption {
    default = ''
      log global
    '';
    type = lines;
    description = ''
      Additional text appended to defaults section of haproxy config.
    '';
  };
};


listenOptions = builtins.foldl' attrsets.recursiveUpdate {} [
  frontendOptions
  backendOptions
  ({
    extraConfig = {
      description = ''
        Additional text appended to a listen section of haproxy config.
      '';
    };
  })
];

frontendOptions = {
  mode = modeOption;
  timeout = timeoutOption;
  options = optionsOption;
  binds = mkOption {
    default = [];
    type = listOf str;
    description = ''
      # `bind [<address>]:<port_range> [, ...] [param*]`
      Defines the binding parameters of the local peer of this "peers" section.
      Such lines are not supported with "peer" line in the same "peers" section.

      From HAProxy Documentation
    '';
  };
  default_backend = mkOption {
    default = null;
    type = nullOr str;
    description = ''
      # `default_backend <backend>`
      Specify the backend to use when no "use_backend" rule has been matched.

      From HAProxy Documentation
    '';
  };
  extraConfig = mkOption {
    default = "";
    type = lines;
    description = ''
      Additional text appended to a frontend section of haproxy config.
    '';
  };
};

backendOptions = {
  mode = modeOption;
  timeout = timeoutOption;
  options = optionsOption;
  balance = balanceOption;
  servers = mkOption {
    default = [];
    type = listOf str;
    description = ''
      # `server <name> <address>[:[port]] [param*]`
      Declare a server in a backend

      From HAProxy Documentation
    '';
  };
  extraConfig = mkOption {
    default = "";
    type = lines;
    description = ''
      Additional text appended to a backend section of haproxy config.
    '';
  };
};

modeOption = mkOption {
  default = null;
  type = nullOr (enum [ "tcp" "http" "health" ]);
  description = ''
    # `mode <mode>`
    Sets the octal mode used to define access permissions on the UNIX socket. It
    can also be set by default in the global section's "unix-bind" statement.
    Note that some platforms simply ignore this. This setting is ignored by non
    UNIX sockets.

    From HAProxy Documentation
  '';
};

timeoutOption = mkOption {
  default = {};
  type = submodule {
    options = let
      timeoutOption = mkOption {
        default = null;
        type = nullOr str;
        description = ''
          Timeout for this event.
        '';
      };
    in {
      check = timeoutOption;
      client = timeoutOption;
      client-fin = timeoutOption;
      connect = timeoutOption;
      http-keep-alive = timeoutOption;
      http-request = timeoutOption;
      queue = timeoutOption;
      server = timeoutOption;
      server-fin = timeoutOption;
      tarpit = timeoutOption;
      tunnel = timeoutOption;
    };
  };
  description = ''
    # `timeout <event> <time>`
    Defines timeouts related to name resolution
      <event> : the event on which the <time> timeout period applies to.
                events available are:
                - resolve : default time to trigger name resolutions when no
                            other time applied.
                            Default value: 1s
                - retry   : time between two DNS queries, when no valid response
                            have been received.
                            Default value: 1s
      <time>  : time related to the event. It follows the HAProxy time format.
                <time> is expressed in milliseconds.

    From HAProxy Documentation
  '';
};

optionsOption = mkOption {
  default = [];
  type = listOf str;
  description = ''
    Options in this list are enabled.
  '';
};

balanceOption = mkOption {
  default = null;
  type = nullOr str;
  description = ''
    # `balance <algorithm> [ <arguments> ]`
    Define the load balancing algorithm to be used in a backend.
  '';
};

in {
  enableStructuredConfig = mkEnableOption "Structured HAproxy Configuration";
  enableLocalPlainConfig = mkEnableOption "Unstructured local HAproxy configuration" // {
    default = true;
  };
  global = mkOption {
    default = {};
    type = submodule {
      options = globalOptions;
    };
    description = ''
      Configuration statements for the global section.
    '';
  };
  defaults = mkOption {
    default = {};
    type = submodule {
      options = defaultsOptions;
    };
    description = ''
      Configuration statements for the defaults section.
    '';
  };
  listen = mkOption {
    default = {};
    example = literalExample ''{
      http-in = {
        binds = [
          "127.0.0.1:8002"
          "::1:8002"
        ];
        default_backend = "be";
      };
    }'';
    type = attrsOf (submodule {
      options = listenOptions;
    });
    description = ''
      Listen sections with statements.
    '';
  };
  frontend = mkOption {
    default = {};
    type = attrsOf (submodule {
      options = frontendOptions;
    });
    description = ''
      Frontend sections with statements.
    '';
  };
  backend = mkOption {
    default = {};
    example = literalExample ''{
      be = {
        servers = [
          "localhost localhost:8080"
        ];
      };
    }'';
    type = attrsOf (submodule {
      options = backendOptions;
    });
    description = ''
      Backend sections with statements.
    '';
  };
  extraConfig = mkOption {
    default = "";
    type = lines;
    description = ''
      Extra configuration statements to be appended.
    '';
  };
}