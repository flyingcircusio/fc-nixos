---
global_sync_id: "v1"
---

# Methods

The API provides two generic XML-RPC methods: one for applying changes to
resources (`apply()`) and one for querying for resource information
(`query()`).

## apply(\[resource_record, ...\])

`apply()` accepts a list of resource records. It is guaranteed that either
all changes will be applied or, when an error occurs, an XML-RPC fault will be
returned and no changes will have been applied. On success the result will be
a list of resource records indicating the new state of the resources.

Resource records are mappings that specify:

`__type__`

: The type of the resource (see [api-resource-types](types.md#api-resource-types)). *Mandatory*.

`__action__`

: The action to perform (`set` or `delete`). If `__action__` is ommitted
  then the API will assume `set` as default.

`any other key`

: defines a value specific to the `__type__`.

```pycon
>>> server.apply([
...     {'__type__': 'virtualmachine', 'name': 'test00', 'cores': 1},
...     {'__type__': 'virtualmachine', '__action__': 'delete', 'name': 'test01'}])
[{'__type__': 'virtualmachine', 'name': 'test00', 'cores': 1, 'memory': 512, ...},
  ...]
```

Resource records may be sparse: only keys that are given will be updated,
others will be kept. You have to pass at least the keys marked as primary keys
for a resource, though. Sparse updates allow you to perform changes without
having to first retrieve and then save the whole record. It also avoids race
conditions that could be introduced through a non-transactional read/update
cycle. The result of `apply()` will always show the full resource records
with all values as they were seen at the end of the transaction.

If you create new resources through the `apply()` method you need to provide
enough data to make the record identifiable (all primary key fields) and
additional fields that are marked as *required*.

Deletions may be processed immediately or delayed. For example, virtual
machines will be deleted over a period of time according to our retention
schedule. Those objects will show that they have been scheduled for deletion
in their resource record.

Also, deleting resources that do not exist is not an error. Deleted or
non-existing objects will not have a result in the response.

## query(type, filter=None)

The `query()` method returns all resources of a given type that are visible
to the current access key. Without any filters this includes the data of
all child projects.

The list of valid types is given in the section [api-resource-types](types.md#api-resource-types).

Filters are specified as a dictionary selecting type-specific keys from the
result for exact matches:

```pycon
>>> server.query('virtualmachine', {'name': 'test00'})
[{'__type__': 'virtualmachine', 'name': 'test00', 'cores': 1, 'memory': 512, ...}]
```

## log(serial=None) { #log-method }

The `log()` method returns all log entries about any call to the other
methods within the same project.  This allows you to integrate our API
logging into your own logging infrastructure by calling this method regularly.
A serial counter assures that you will receive only new logs and not miss any
logs.

A few rules:

- Logs are kept 30 days.
- Calls to the `log()` method are not logged themselves.
- If a project is deleted, then all associated logs are deleted immediately, too.
- Please do not poll the API in extremely short cycles.
  Let's say once every few minutes is sufficient.
- Logs only contain calls from the exact API key associated with the project. Calls with access keys from child projects are not shown in the parent log.
- Logs are kept when the API key is reset.

How to ensure that you receive a gapless log:

- For the first call you can omit the optional parameter `serial`
  which will return the latest 10 records.
- For future calls you should remember the highest `serial` that you have
  seen in the past and pass it by calling `log(serial)`.

Here's an example:

```pycon
>>> server.query('virtualmachine')
[]
>>> server.log()
[{'args': '{"args": ["virtualmachine"], "kw": {}}',
  'exception': '',
  'ipaddress': '127.0.0.1',
  'method': 'query',
  'resource_group': 'services',
  'result': '[]',
  'serial': 2,
  'timestamp': '2015-12-23 01:02:03'}]
>>> server.log(2)
[]
```

!!! note
    The data for `args` and `result` in
    the log are JSON-encoded strings.
