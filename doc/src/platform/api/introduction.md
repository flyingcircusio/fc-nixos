---
global_sync_id: "v1"
---

# Introduction

Our API is provided as an [XML-RPC](https://de.wikipedia.org/wiki/XML-RPC)
endpoint at the URL <https://api.flyingcircus.io/v1>. We use [Apache's XML-RPC
extensions](https://ws.apache.org/xmlrpc/extensions.html)  to
support `null` values and `long` integer types.

There are two methods implemented (`query()` and `apply()`) that work on
resources like virtual machines, user permissions, projects, maintenance
windows, and so on.

```pycon
>>> import xmlrpclib
>>> xmlrpclib.ServerProxy("https://api.flyingcircus.io/v1")
>>> server.apply([{'__type__': 'virtualmachine', 'name': 'test00', 'memory': 1024}])
```

The API is designed with idempotence and transactional behaviour in mind to
support reliability: re-playing actions will always cause the same result as
the first time and you can group together changes that are either applied all
at once or not at all.

Changes applied to resources are stored in our inventory database when
calling the API. There is no guarantee that any change is applied to the
actual objects on our platform within a given period of time.

For example: changing the RAM of a virtual machine will update the record
in our database. This in turn causes maintenance to be scheduled for a
controlled reboot of the VM depending on the project's maintenance
window configuration.

## Confidentiality

Access to the API is intended to be confidential. We provide the API only
through HTTPS. We continuously monitor for the quality of the certificate
and webserver settings.

## Authentication

To interact with the API you need to authenticate within the context of
a project. For every project there exists an API key that can
be managed from the [self-service UI API dashboard](https://my.flyingcircus.io/api/tokens).

Authentication happens through HTTP Basic Auth with the username being
the name of the project and the password being the access key
for this project.

```pycon
>>> xmlrpclib.ServerProxy(
...     "https://test:dfbc66df66dc5d@api.flyingcircus.io/v1")
```

## Authorization

Access to any resource is granted based on the relation of the project
the access key belongs to. A key is granted either full access (r/w)
to any object within the project or no access at all. This includes
all objects of any child projects.

!!! note
    The API key can not be used to delete the project it belongs to.
    It can only delete child projects.

## Limits

The API may enforce semantic limits on the application of changes:

- resource limits to avoid exceeding the capacity and redundancy of our
  infrastructure (RAM, CPU, disk)
- credit limits to avoid exceeding the value of services a customer is willing
  to pay for (limit per project and its children, based on a projection
  of the additional monthly cost of adjusted resources)

When limits are enforced the API will return a specific fault indicating this.

We expect customers to perform a reasonable number of API requests without
enforcing them at the moment. Consider caching data on your side and performing
adequate batch queries in `apply()` and `query()` to avoid overloading our
systems with requests.

In the future we may introduce specific and hard technical limits on the number
of API calls within a period of time.
