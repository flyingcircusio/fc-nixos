(nixos-ferretdb)=

# FerretDB

:::{note}
FerretDB support is in beta. Feel free to use it but we suggest contacting
our support before putting anything into production.
:::

Managed instance of [FerretDB](https://www.ferretdb.io), an Apache-licensed
MongoDB alternative supporting multiple backend stores.

## Configuration

FerretDB works out-of-the box without configuration.
PostgreSQL is used as default backend. We automatically enable PostgreSQL and
create a database `ferretdb` owned by the `ferretdb` user.
Updates to new PostgreSQL versions are done automatically as long as there's only
the `ferretdb` database in it.

FerretDB supports only one listen address. By default, it listens to the SRV
interface, port 27017 like MongoDB, using IPv4.

## Command Line Interface

As FerretDB is mostly line protocol-compatible with MongoDB, you can use tools
built for MongoDB. We install `mongodb-tools` and `mongosh` globally by default.

Use {command}`mongosh` to query and update data as well as perform
administrative operations:

```shell
mongosh $HOST
```

## Authentication

Authenticating connections to FerretDB is not supported at the moment.
(nixos-ferretdb-upgrade)=

## Migrating from MongoDB

:::{warning}
Feature compatibility with MongoDB (namely version 6) is good and FerretDB is
mostly a drop-in replacement. However, make sure to properly test your
application with FerretDB in a staging environment before rolling it out to
production.
:::

Data dumps from MongoDB can be imported into a FerretDB instance.

On the FerretDB machine called `example01`, dump all collections from a
MongoDB instance running on `example03`, assuming default configuration of
the MongoDB role with no authentication needed.

See http://docs.mongodb.com/database-tools/mongodump/ for more information.


```shell
mongodump mongodb://example03 -o mongodb_dump
```

Import dump to FerretDB:

```shell
mongorestore mongodb://example01 mongodb_dump
```

## Monitoring

Our monitoring checks that the ferretdb daemon is running and responds to requests.
We also monitor the underlying PostgreSQL instance.
