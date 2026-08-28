---
global_sync_id: "v1"
---

% last review: 2026-05-07

% review schedule: 1 year

% ISMSControl: A.9.2.2
% ISMSControl: 5.18


![](../../images/users250.png){ .logo }

# User accounts { #useraccounts }

## Principles

- Users are distinguished as human or service users.
- All users of a resource group are configured (e.g. visible via `getent`) on all
  nodes of a resource group.
- The following attributes are globally unique: UID for users; group
  name and GID for groups. 
- The presence of an account alone does not imply any permission assignments.

## Human users

- The username is globally unique and must not start with `s-`.
- The primary group is `users`.
- The home directory is located in `/home/$USER`.

## Service users { #service-users }

- The primary group is `service`.
- Usernames usually start with `s-` and are unique within a resource group.
  Different resource groups can reuse the same service user names.
- The home directory is located in `/srv/$USER`.
- No SSH login is allowed by default to support the general data protection guidelines. In exceptional cases SSH access may be granted.
- Human users that have the *sudo-srv* permission in a project are
  allowed to change to the service user (`sudo -u <service_user_name>   -i`) and execute commands as a service user (`sudo -u   <service_user_name> <command>`).

## Permissions { #permissions }

Users own a separate set of permissions for every project they are a
member of. Common permissions include:

login

: Perform interactive shell login on a machine (via SSH).

manager

: Add or remove other users from the project. Define permissions for users in the project.

sudo-srv

: Sudo into service users on a machine (password not necessary)
