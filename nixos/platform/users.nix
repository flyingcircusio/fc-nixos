{ config, lib, pkgs, ... }:

# Flying Circus user management
#
# UID ranges
#
# 30.000 - 30.999: reserved for nixbldXX and NixOS stuff
# 31.000 - 65.534: reserved for Flying Circus-specific system user
#
#
# GID ranges
#
# 30.000 - 31.000: reserved for NixOS-specific stuff
# 31.000 - 65.534: reserved for Flying Circus-specific system groups

with builtins;

let

  cfg = config.flyingcircus.users;

  fclib = config.fclib;

  primaryGroup = user:
    getAttr user.class {
      human = "users";
      service = "service";
    };

  # Data read from Directory (list) -> users.users structure (list)
  mapUserData = users: serviceUserExtraGroups:
    lib.listToAttrs
      (map
        (user: {
          name = user.uid;
          value = {
            description = user.name;
            group = primaryGroup user;
            extraGroups =
              lib.optionals (user.class == "service") serviceUserExtraGroups;
            hashedPassword = lib.removePrefix "{CRYPT}" user.password;
            home = user.home_directory;
            isNormalUser = true;
            openssh.authorizedKeys.keys = user.ssh_pubkey;
            shell = "/run/current-system/sw${user.login_shell}";
            uid = user.id;
          };
        })
      users);

  currentRG = with config.flyingcircus;
    if lib.hasAttrByPath [ "parameters" "resource_group" ] enc
    then enc.parameters.resource_group
    else null;

  groupMembershipsFor = user:
    if currentRG != null && lib.hasAttr currentRG user.permissions
    then
      lib.listToAttrs
        (map
          # making members a scalar here so that zipAttrs automatically joins
          # them but doesn't create a list of lists.
          (perm: { name = perm; value = { members = user.uid; }; })
          (getAttr currentRG user.permissions))
    else {};

  # user list from directory -> { groupname.members = [a b c], ...}
  groupMemberships = users:
    lib.mapAttrs (name: groupdata: lib.zipAttrs groupdata)
      (lib.zipAttrs (map groupMembershipsFor users));

  permissionGroups = permissions:
    lib.listToAttrs
      (filter
        (group: group.name != "wheel")  # This group already exists
        (map
          (permission: {
            name = permission.name;
            value = {
              gid = config.ids.gids.${permission.name};
            };
          })
          permissions));

  homeDirPermissions = userdata:
    map (user: ''
      install -d -o ${toString user.id} -g ${primaryGroup user} -m 0755 ${user.home_directory}
    '')
    userdata;

  # merge a list of sets recursively
  mergeSets = listOfSets:
    if (length listOfSets) == 1 then
      head listOfSets
    else
      lib.recursiveUpdate
        (head listOfSets)
        (mergeSets (tail listOfSets));

  htpasswdUsers = lib.optionalString
    (config.users.groups ? login)
    (concatStringsSep "\n"
      (map
       (user: "${user.name}:${user.hashedPassword}")
       (filter
        (user: (stringLength user.hashedPassword) > 0)
        (map
         (username: config.users.users.${username})
         (config.users.groups.login.members)))));

in
{

  options.flyingcircus.users = with lib.types; {

    serviceUsers.extraGroups = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
      description = ''
        Names of groups that service users should (additionally)
        be members of.
      '';
    };

    userData = lib.mkOption {
      type = listOf attrs;
      description = "All users local to this system.";
    };

    userDataPath = lib.mkOption {
      default = /etc/nixos/users.json;
      type = path;
      description = "Where to find the user json file.";
    };

    permissions = lib.mkOption {
      type = listOf attrs;
      description = "All permissions known on this system.";
    };

    permissionsPath = lib.mkOption {
      default = /etc/nixos/permissions.json;
      type = path;
      description = ''
        Where to find the permissions json file.
      '';
    };

    adminsGroup = lib.mkOption {
      type = attrs;
      description = "Super admins GID and contact addresses.";
    };

    adminsGroupPath = lib.mkOption {
      default = /etc/nixos/admins.json;
      type = path;
      description = ''
        Where to find the admins group json file.
      '';
    };

  };

  config = {

    # All login users as htpasswd compatible file
    environment.etc."local/htpasswd_fcio_users".text = htpasswdUsers;

    flyingcircus.users = with lib; {
      userData = mkDefault (fclib.jsonFromFile cfg.userDataPath "[]");
      permissions = mkDefault (fclib.jsonFromFile cfg.permissionsPath "[]");
      adminsGroup = mkDefault (fclib.jsonFromFile cfg.adminsGroupPath "{}");
    };

    security.pam.services.sshd.showMotd = true;

    security.sudo = {
      extraConfig = ''
        Defaults set_home,!authenticate,!mail_no_user
        Defaults lecture = never
      '';

      # needs to be first in sudoers because of the %admins rule
      extraRules = lib.mkBefore [
        # Allow unrestricted access to super admins
        {
          groups = [ "admins" ];
          commands = [ { command = "ALL"; options = [ "PASSWD" ]; } ];
        }
        # Allow sudo-srv users to become service user
        { groups = [ "sudo-srv" ]; runAs = "%service"; commands = [ "ALL" ]; }
        # Allow applying config and restarting services to service users
        {
          groups = [ "sudo-srv" "service" ];
          commands = [ "${pkgs.systemd}/bin/systemctl" ];
        }
      ];
    };

    services.openssh.extraConfig = ''
      AllowGroups root admins login
    '';

    users =
      let adminsGroup =
        lib.optionalAttrs (cfg.adminsGroup != {})
        { ${cfg.adminsGroup.name}.gid = cfg.adminsGroup.gid; };
      in {
      mutableUsers = false;
      users = mapUserData cfg.userData cfg.serviceUsers.extraGroups;
      groups = mergeSets [
          adminsGroup
          { service.gid = config.ids.gids.service; }
          (groupMemberships cfg.userData)
          (permissionGroups cfg.permissions)
        ];
    };

    system.activationScripts.fc-homedir-permissions =
      lib.stringAfter [ "users" ]
      (concatStringsSep "\n" (homeDirPermissions cfg.userData));

  };
}
