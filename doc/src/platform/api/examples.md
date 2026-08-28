---
global_sync_id: "v1"
---

# Examples

Here is a sample walkthrough how to use the API with the default Python
`xmlrpclib` client to create a new project, a VM, a service user, and
grant permissions to a human user. The walk through can be recreated using
the same credentials with our Vagrant-based test environment:

```pycon
>>> import xmlrpclib, ssl
>>> if hasattr(ssl, '_create_unverified_context'):
...     ssl._create_default_https_context = ssl._create_unverified_context
>>> s = xmlrpclib.ServerProxy(
        'https://services:20a64405dbeb667e286eb3e777b90f25a985b1aa@'
        'api.192.168.50.4.nip.io/v1')
>>> s.ping()
'pong'
```

We start out with a master project that the API key is granted to:

```pycon
>>> s.query('resourcegroup')
[{'__type__': 'resourcegroup',
  'customer_no': '',
  'maintenance_end': 5,
  'maintenance_start': 22,
  'name': 'services',
  'notification_leadtime': 12,
  'parent': '',
  'production': True,
  'technical_contacts': ['admin@flyingcircus.io'],
  'timezone': 'Europe/Berlin'}]
```

We create a new project with only minimal details and get the
full record back:

```pycon
>>> s.apply([{'__type__': 'resourcegroup', 'name': 'example'}])
[{'__type__': 'resourcegroup',
  'customer_no': '',
  'maintenance_end': 5,
  'maintenance_start': 22,
  'name': 'example',
  'notification_leadtime': 12,
  'parent': 'services',
  'production': True,
  'technical_contacts': [],
  'timezone': 'Europe/Berlin'}]
```

Now we can create a VM in this project:

```pycon
>>> s.apply([{'__type__': 'virtualmachine',
...           'name': 'example00',
...           'resource_group': 'example',
...           'location': 'vgr'}]
[{'__type__': 'virtualmachine',
  'classes': ['role::backupclient', 'role::customerproject'],
  'cores': 1,
  'deletion': {'deadline': '', 'stages': []},
  'disk': 10,
  'environment': 'production',
  'frontend_ips_v4': 1,
  'frontend_ips_v6': 0,
  'id': 4103,
  'interfaces': {'fe': {'mac': '02:00:00:02:10:07',
                        'networks': {'192.168.2.0/24': ['192.168.2.5']}},
                 'srv': {'mac': '02:00:00:03:10:07',
                         'networks': {'192.168.3.0/24': ['192.168.3.5']}}},
  'kvm_host': '',
  'location': 'vgr',
  'machine': 'virtual',
  'memory': 256,
  'name': 'example00',
  'online': True,
  'production': True,
  'resource_group': 'example',
  'resource_group_parent': 'services',
  'reverses': {},
  'service_description': '',
  'servicing': True,
  'timezone': 'Europe/Berlin'}]
```

!!! note
    The location identifies the datacenter you want to place the virtual
    machine in and is required. It cannot be changed unless you delete
    the VM first. The test environment has a location named `'vgr'`
    available. Our production data center is called `'rzob'`.

To let the VM do something useful, we can select classes:

```
>>> s.apply([{'__type__': 'virtualmachine', 'name': 'example00',
              'classes': ['role::appserver', 'role::webgateway']}])
[{'__type__': 'virtualmachine',
  'classes': ['role::appserver',
              'role::backupclient',
              'role::customerproject',
              'role::webgateway'],
...
```

Now, lets create a service user for this project:

```pycon
>>> s.apply([{'__type__': 'serviceuser',
...           'uid': 's-example',
...           'resource_group': 'example'}])
[{'__type__': 'serviceuser',
  'description': '',
  'gid_number': 101,
  'home_directory': '/srv/s-example',
  'id_number': 1001,
  'login_shell': '/bin/bash',
  'resource_group': 'example',
  'resource_groups_recursive': ['example'],
  'ssh_pubkey': [],
  'uid': 's-example',
  'virtual_machines': ['example00']}]
```

And now lets make the "Admin" user part of this project with
the right to log in and change into the service user:

```
>>> s.apply([{'__type__': 'permission',
...           'permission': 'login',
...           'resource_group': 'example',
...           'uid': 'admin'},
...          {'__type__': 'permission',
...           'permission': 'sudo-srv',
...           'resource_group': 'example',
...           'uid': 'admin'}])
[{'__type__': 'permission',
  'permission': 'login',
  'resource_group': 'example',
  'uid': 'admin'},
 {'__type__': 'permission',
  'permission': 'sudo-srv',
  'resource_group': 'example',
  'uid': 'admin'}]
```

Note that we used the batch-version of `apply()` to create two records
at once. We also get both records back.

Additionally, you can just run all of those commands in a single big
transaction and have either all of them executed, or none of them. However:
you need to specify them in the order as if you executed them step by step  to
avoid internal dependency issues.

```pycon
>>> s.apply([
... {'__type__': 'resourcegroup',
...  'name': 'example'},
... {'__type__': 'virtualmachine',
...  'name': 'example00',
...  'resource_group': 'example',
...  'location': 'vgr',
...  'classes': ['role::appserver', 'role::webgateway'},
... {'__type__': 'serviceuser',
...  'uid': 's-example',
...  'resource_group': 'example'}
... {'__type__': 'permission',
...  'permission': 'login',
...  'resource_group': 'example',
...  'uid': 'admin'},
... {'__type__': 'permission',
...  'permission': 'sudo-srv',
...  'resource_group': 'example',
...  'uid': 'admin'}])
[...output of all records as above...]
```
