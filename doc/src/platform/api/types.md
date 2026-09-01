---
global_sync_id: "v1"
---

# Resource Types { #api-resource-types }

The API supports various resource types. Some of them can be queried and
updated, others can only be queried.

Each type has a set of identifying keys which correspond to the RDBMS
"primary key" concept. When updating or deleting a record you need to specify
at least the primary key to ensure unambiguity.

## Resource Group

Resource group are the foundational building block for organizing resources
in the Flying Circus platform: they form groups of (virtual) machines and
control which users have permissions for them, what rules to apply for maintenance,
and more.

In addition to the resource group that your key is associated with, you
can create new child resource groups.

The structure of a resource group record looks like this:

```python
{'__type__': 'resourcegroup',
 'customer_no': '',
 'in_maintenance': False,
 'maintenance_end': 5,
 'maintenance_start': 22,
 'maintenance_until': '',
 'name': 'services',
 'notification_leadtime': 12,
 'parent': '',
 'production': True,
 'technical_contacts': ['admin@flyingcircus.io'],
 'timezone': 'Europe/Berlin'}]
```

name

: *read-only, primary key, filterable*

  The name of the resource group. Needs to be a valid Linux group name.

customer_no

: *readonly, filterable, default: inherited or pre-set*

  The customer number of the customer who is charged for resources
  that belong to this resource group.

in_maintenance

: *bool, default:* `False`

  True, if the resource group is in maintenance mode. This prevents alerting FC staff.

  Maintenance will be limited to 1 hour from initial setting the value and automatically reset.

  An error is returned if `in_maintenance` and `maintenance_until` have contradicting values.

maintenance_start

: *filterable, default:* `22`

  Hour in the day when scheduled maintenance windows may start.

maintenance_end

: *filterable, default:* `5`

  Hour in the day when scheduled maintenance windows should end.

maintenance_until

: *datetime* (ISO 8601 with time zone)

  The resource group is in maintenance until the given date.

  Set to an empty string or a date in the past to end maintenance.

  An error is returned if `maintenance_until` and `in_maintenance` have contradicting values.

notification_leadtime

: *filterable, default:* `12`

  Number of hours that technical contacts should be informed upfront
  about maintenance windows.

timezone

: *filterable, default:* `'Europe/Berlin'`

  The name of a timezone that VMs should be running in and that
  any time specifications (like maintenance windows) should be
  relative to.

parent

: *default:* `''`

  Name of the parent resource group if this resource group has one.

  If you create new resource groups, this will be set to the name
  of the resource group that your API key belongs to. Alternatively
  you can set the parent to any resource group that your API key
  has access to.

  (Making new top-level projects does not make much sense as
  they would become inaccessible to your API key anyway.)

production

: *filterable, default:* `True`

  Indicates whether the services of this resource group are considered
  for production use (in contrast to testing, staging, dev, or similar
  non-production instances).

technical_contacts

: *default:* `[]`

  A list of strings specifying email addresses that should be notified
  of technical updates (monitoring, maintenance windows, ...).

## Service users

Service users are used to run your actual services - compared to running them
in your login user.  This gives additional security and allows more flexible
workflows when cooperating with other team members.

In nested projects, service users exist on all child projects
recursively.

You can query, create, update and delete service users. Their names always
start with `s-` to make them distinguishable from regular users. Their names
are unique per resource group, so you can have multiple services users named
`s-myservice` in different projects.

The structure of a service user record looks like this:

```python
{'__type__': 'serviceuser',
 'description': '',
 'gid_number': 101,
 'home_directory': '/srv/s-services',
 'id_number': 1000,
 'login_shell': '/bin/bash',
 'resource_group': 'services',
 'resource_groups_recursive': ['services'],
 'ssh_pubkey': [],
 'uid': 's-services',
 'virtual_machines': []}
```

uid

: *needs to be set on create, read-only otherwise; primary key; filterable*

  The Linux name of this service user. Needs to start with `s-` and
  be unique within each resource group.

resource_group

: *needs to be set on create, read-only otherwise; primary key*

  The name of the resourcegroup this service user belongs to.

resource_groups_recursive

: *read-only*

  The flattened list of names of all projects that this
  service user has access to.

description

: *default:* `''`

  A descriptive text that will be displayed in the context of this service
  user to clarify its purpose.

id_number

: *read-only*

  The numerical id that this user has on Linux machines.

gid_number

: *read-only, default:* `101`

  The numerical id of the primary group that this user wears on Linux
  machines.

home_directory

: *read-only, default:* `'/srv/<uid>'`

  The home directory that this user has on Linux machines. Historical users
  may deviate from that schema. The record is kept to avoid unnecessarily
  moving data around.

login_shell

: *read-only, default:* `'/bin/bash'`

  The service user may have a deviating login shell in special circumstances.
  Normally it's just bash.

ssh_pubkey

: *read-only, default:* `[]`

  The service user can be permitted to log in via SSH (although we do
  not recommend this normally). To set a service users's SSH keys, please
  use the [self-service UI](https://my.flyingcircus.io).

virtual_machines

: *read-only*

  The names of all the virtual machines that this service user has
  access to.

## User permissions

Permissions are assigned to users (human and service) on a per-resource group
basis and control the access level that users have to login and interact with
virtual machines and other services.

The available permissions are:

`login`

: Grants the user the ability to log into virtual machines by SSH.
  Does not allow the user to configure or control services on the machines.

`sudo-srv`

: Grants the user the ability to configure and control services on
  the machines by sudoing into service user accounts after logging
  in via SSH.

`stats`

: Grants the user (read-only) access to statistical backend services like
  Nagios, PNP, Kibana, awstats and others.

Permission records look like this:

```python
{'__type__': 'permission',
 'permission': 'test',
 'resource_group': 'services',
 'uid': 's-services'}
```

permission

: *read-only, primary key*

  The name of the permission that is granted.

resource_group

: *read-only, primary key*

  The name of the resource group the permission is granted.
  Applies to child projects as long as the child resource
  group does not define any other permission.

uid

: *read-only, primary key, filterable*

  The uid of the user that this permission applies to. Can apply to
  human and service users.

## Virtual Machines { #api-virtual-machines }

The API allows querying, creating, updating, and deleting the VM resources
that your services need.

Creation of VMs may take a while: you can be sure that a machine is ready
to use when the `needs_install` flag is set to `False`.

Updates to VM propagate depending on your change. Virtual hardware changes
may take a while to be applied and may even require a maintenance window.

Creation or changes to the VM's resources may be rejected if it would
exceed safety thresholds of our data centers. There are also some limits
given by the API to avoid accidents.

A virtual machine record looks like this:

```python
{'__type__': 'virtualmachine',
 'classes': ['role::generic'],
 'cores': 1,
 'creation_date': '2015-01-02T03:04:05+00:00',
 'deletion': {'deadline': '', 'stages': []},
 'disk': 10,
 'environment': '',
 'id': 4100,
 'interfaces': {'fe': {'mac': '02:00:00:02:10:04', 'networks': {}},
                'srv': {'mac': '02:00:00:03:10:04',
                        'networks': {'192.168.0.0/24':
                                     ['192.168.0.2']}}},
 'kvm_host': '',
 'last_maintenance_end': '',
 'location': 'rzob',
 'machine': 'virtual',
 'memory': 256,
 'name': 'services10',
 'online': True,
 'production': True,
 'resource_group': 'services',
 'resource_group_parent': '',
 'frontend_ips_v4': 0,
 'frontend_ips_v6': 0,
 'reverses': {},
 'service_description': '',
 'servicing': True,
 'timezone': 'Europe/Berlin'}
```

name

: *read-only, primary key*

  The name of the virtual machine. All machines within a resource group
  need to adhere to the schema `<nameofrg><serialnumber>`. You can choose
  how to allocate those numbers as you like.

  We typically use `00` for the frontend machine, the numbers
  `01` - `09` are typically for singular services like databases,
  mailservers, and other auxiliary things.

  Higher numbers typically indicate clusters of application instances, like
  `10` - `30` being instances of your application.

resource_group

: *readonly, required*

  The name of the resource group this VM belongs to.

location

: *readonly, required*

  The data center that this VM is running in. Can only (and must) be set
  to `'rzob'`, our only public data center at the moment.

id

: *read-only*

  A globally unique integer ID identifying this VM instance.

service_description

: *default:* `''`

  A textual description of the purpose of this VM. This will be shown
  in appropriate places, e.g. as MOTD when logging in to the VM.

resource_group_parent

: *readonly*

  The name of the parent resource group of the resource group this
  VM belongs to.

  > 'timezone': 'Europe/Berlin'

classes

: *default*: `['role::generic', 'role::backupclient']`

  Those are names for the "managed components", or "roles" that we provide
  to install on your machine. You can find details about each class
  in the specific platform release documentation.

  A few roles are not selectable by you: if your VM runs in a production
  resource group, it will always be marked as `role::backupclient` to
  ensure safety of your data.

  Generally your VM will always have the `role::generic` class applied.

  Removing those classes is ignored.

environment_class

: The `environment_class` is the general flavor of your VM. Possible values are:

  - `NixOS`
  - `Puppet` (Gentoo platform, obsolete)

  !!! note
      The `environment_class` must be set coherently with the `environment`.
      The `environment_class` can not be changed without deleting the VM (and
      going through the recycling period) first.

environment

: The environment is the rolling-release version of our platform and
  management code.

  The available environments depend on the environments class:

  - NixOS
    - `fc-22.05-production`
    - `fc-22.05-staging`
    - `fc-21.11-production`
    - `fc-21.11-staging`
    - Outdated environments:
      - `fc-21.05-production`
      - `fc-21.05-staging`
      - `fc-20.09-production`
      - `fc-20.09-staging`
      - `fc-19.03-production`
      - `fc-19.03-staging`
      - `fc-15.09-production`
      - `fc-15.09-staging`
  - Puppet: `production`, `staging`

cores

: *default*: `1`

  The number of virtual cores assigned to the VM. A maximum of 8 cores
  can be assigned per VM. If you need more:
  [contact us](mailto:support@flyingcircus.io).

  Changing the number of cores will schedule a maintenance window to
  reboot the VM.

memory

: *default*: `256`

  The amount of memory assigned to the VM in MiB. The minimum of 256 MiB
  can not be undercut. Through the API you can assign a maximum of 3072 MiB
  (or 3 GiB) to a single VM. If you need more:
  [contact us](mailto:support@flyingcircus.io).

  Changing the amount of memory will schedule a maintenance window to
  reboot the VM.

disk

: *default*: `10`

  The amount of disk space assigned to the root disk (`/`) of your VM
  in GiB. The minimum of 10 GiB can not be undercut. Through the API
  you can assign a maximum of 1000GiB to a virtual machine.

  We provide auxiliary space for `/tmp` and `swap` for free.

  Increasing the amount of disk space will perform an online resize within
  a few minutes.

  Decreasing the amount of disk space will schedule a maintenance window
  to reboot the VM.

rbd_pool

: *default*: `rbd.hdd`

  Set the storage pool for the VM. Possible values are:

  - `rbd.hdd` for HDD backed storage, and
  - `rbd.ssd` for SSD backed storage.

  !!! note
      This value can only be set when the VM is created, and cannot be changed later.

online

: *default*: True

  Indicates if the VM *should* be running (True) or not (False).

  Setting `online` to `False` will properly shutdown the VM, if possible. If the shutdown fails, the VM will be killed.

interfaces

: *readonly*

  A hierarchy of VLANs, the assigned IP networks (4 and 6)
  and the associated IP addresses for the VM.

  `srv` indicates the server-to-server communication channel.
  Those machines will only be assigned private IPv4 addresses but
  public IPv6 addresses. `fe` indicates public internet traffic.

reverses:

: *readonly*

  A list of IP addresses and registered reverse DNS names. We can set
  those for you if you contact us.

frontend_ips_v4

: *default:* `0`

  The number of public IPv4 addresses to allocate for this VM. Increasing this
  number will cause more addresses to be allocated. Decreasing this number
  will *not* remove IP addresses at this time. [Contact us](mailto:support@flyingcircus.io) if you want to reduce this number.

!!! note
    Public IPv4 addresses are a scarce resource. Most virtual machines
    do not require one. Typically you need only 1 per resource group,
    maybe 2 or 3 under certain conditions. In the case of excessive use
    we may reduce the number of IPs available to your VM.

    The number of public IPv4 addresses is limited to 3 per machine.

    If you have a special case that justifies using more IPv4 addresses, please
    [talk to us](mailto:support@flyingcircus.io) and we will be happy to work
    on a solution with you.

frontend_ips_v6

: *default:* `0`

  The number of public IPv6 addresses to allocate for this VM. Increasing this
  number will cause more addresses to be allocated. Decreasing this number
  will *not* remove IP addresses at this time. [Contact us](mailto:support@flyingcircus.io) if you want to reduce this number.

  The API limits you to 100 public IPv6 addresses per virtual machine.

backy_schedule

: *default:* `default`

  The backy schedule defines how often the VM is backed up and how long the backups are retained. See [the backup documentation](../../infrastructure/backup.md) for possible values.

machine

: *readonly*

  Indicates that this is a virtual machine. In the future we may provide
  access to physical machines which would have similar records but
  display `physical` instead of `virtual` in this place.

kvm_host

: *readonly*

  The hostname of the machine running your VM. Given for informative
  purposes. Sometimes having two VMs run on the same host may give
  significantly different networking results.

production

: *readonly*

  Reflects the setting of this VM's `production` flag - see above.

servicing

: *readonly, default:* `True`

  Reflects whether this VM is assumed to be doing purposeful things at the
  moment. During maintenance this may be set to `False` and may be used
  by our infrastructure to temporarily do things to this VM that would
  not be appropriate if it was busy.

last_maintenance_end

: *readonly*

  The date and time when the VM was last in maintenance mode,  ISO 6801 formatted with time zone. This can be useful to correlate with monitoring results. For instance you could ignore monitoring errors for a certain time after the maintenance ended to avoid notifications.

creation_date

: Date and time when the VM has been created, ISO 6801 formatted with
  time zone.

deletion

: *readonly, default:* `{'deadline': '', 'stages': []}`

  Reflects the deletion state of this VM. Reflects the deadline and
  the stages of the deletion that have been reached already.

### Deleting a virtual machine

If you delete a VM without any options it will be marked for deletion by the
end of the current month. After that it will not be accounted for any longer
and will be shut down, and unconfigured. The data will be deleted over a period
of about 1 month -- which grants you some time to notice if you accidentally
deleted the wrong VM. The VM's record will be shown in queries until a few days
after its deadline.

Additionally you can pass the field `deadline` with an ISO date:

```pycon
>>> server.apply([
...     {'__type__': 'virtualmachine',
...      '__action__': 'delete',
...      'deadline': '2020-01-01',
...      'name': 'services10'}])
```

!!! note
    Deletions must be scheduled in the future. The earliest possible
    day is always "tomorrow". Our timezone is Europe/Berlin for this.

To cancel a pending VM deletion you can simply update the VM without giving
any additional data:

```pycon
>>> server.apply([{'__type__': 'virtualmachine', 'name': 'services10'}])
```

## Maintenance

The API allows querying maintenance windows and activities that have been
scheduled for your services. Maintenance windows can not be changed
through the API.

General parameters for maintenance windows can be configured on the
corresponding resource group object.

A maintenance record looks like this:

```python
{'__type__': 'maintenance',
 'active': True,
 'activities': [{'comment': 'test',
                 'duration': 0,
                 'ended': False,
                 'estimated': 100,
                 'reference_id': '',
                 'result': '',
                 'starts': '2011-07-02T20:00:00+00:00'}],
 'announced': False,
 'comment': '',
 'ends': '2011-07-03T03:00:00+00:00',
 'machine': 'kyle10',
 'starts': '2011-07-02T20:00:00+00:00'}
```

Times are given in UTC.

## Consumptions

The API allows querying consumptions. Consumptions are used to account for
things that you as a customer use or "consume" on our platform. At the
end of a month, those consumptions are reviewed and turned into invoice items.

Consumptions can be queried during a month to see the ongoing view of
your traffic, virtual machines, contracts, and more. Consumptions are also
historic data and remain available even if you delete a resource group, a VM,
or pass your resources over to a different customer.

Access to consumptions is granted based on the customer of the resource
group that your API key is registered for.

A consumption record looks like this:

```python
{'__type__': 'consumption',
 'customer_no': '12345',
 'parameters': {'traffic': 12345678104378L},
 'period': '2015-01-01',
 'type': 'traffic',
 'type_id': 'myrg'}
```

The content of `type_id` depends on the type. For example: traffic is
accounted per resource group. Virtual machines are accounted per virtual
machine. Parameters vary per type as well.

## Invoices

The API allows querying invoices. Invoices are generated on a monthly
basis for each customer based on the corresponding consumptions.

Invoices are send out by email in PDF format automatically and can be
retrieved in an automatic fashion from the API. However, due to the
complexities of international taxes, we only show pre-tax information
through the API.

An invoice record looks like this:

```python
{'__type__': 'invoice',
     'consumption_end': '2012-01-31',
     'consumption_start': '2012-01-01',
     'customer_no': '12345',
     'items': [{'description': 'test item',
                'price': '10.0000',
                'product': 'PRODUCT1234'}],
     'status': 'pending',
     'total': '10.0000'}
```
