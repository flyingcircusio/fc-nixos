# Open WebUI { #nixos-role-open-webui }

Managed instance of the [Open WebUI](https://openwebui.com/) LLM interface. It automatically integrates with the *Flying Circus AI services*.
% TODO: link to more general FC AI docs/ overview

## Initial Setup


% TODO: link to subscription, verify subscription naming

A *Flying Circus AI Services* subscription is required for this role. An access token must be created in the customer portal to allow the Open WebUI instance to access our central AI gateway.

Enabling the `open-webui` role automatically sets up Open WebUI available under `https://ai-chat.<resource group>.fcio.net`. The access token from the customer portal must then be copied into the file `/etc/local/open-webui/secret` on the VM with the role assigned. As the first account accessing the application after installation automatically gains administrator privileges, we recommend that a designated administrator logs in immediately after the role is assigned and configured.

## User Management

User access is centrally managed via [Flying Circus users](../platform/users/index.md). By default, all members of the resource group are able to log in to the service.  \
To require the approval of an Open WebUI administrator, set `flyingcircus.roles.open-webui.usersNeedApproval = true;` via NixOS config. New users may then be approved by clicking their *pending* role badge in the administrator interface.

User roles and groups have to be manually managed in the Open WebUI administrator settings. The first user successfully logging in after the initial setup of the role receives administrator privileges. Additional administrators can be authorised by that user in the Open WebUI administrator interface.

## Available AI Models

All models available through our *Flying Circus AI services* are automatically discovered by Open WebUI, but are only available to administrators by default. Under *Administration -> Settings -> Models*, each model can be either set public or be made accessible to certain groups.
