import csv
import io
import os
import pathlib
import subprocess
import sys

DATADIR = sys.argv[1]

IGNORE = "template0"

GET_AFFECTED_OBJECTS = """
SELECT pg_describe_object(refclassid, refobjid, refobjsubid) AS "Collation",
       pg_describe_object(classid, objid, objsubid) AS "Object"
FROM pg_depend d JOIN pg_collation c
     ON refclassid = 'pg_collation'::regclass AND refobjid = c.oid
WHERE c.collversion <> pg_collation_actual_version(c.oid)
ORDER BY 1, 2;
"""

GET_COLLATION_VERSIONS = """
SELECT datname, datcollate AS db_collation,
       datcollversion,
       pg_database_collation_actual_version(oid) AS oscollversion
FROM pg_database
WHERE datname != 'template0'
"""


def psql(*args):
    env = os.environ.copy()
    env["PGCLIENTENCODING"] = "utf-8"
    output = subprocess.check_output(
        ("psql", "--csv") + args, env=env, encoding="utf-8"
    )
    output = io.StringIO(output)
    rows = csv.DictReader(output, delimiter=",", quotechar='"')
    return rows


print("Verifying database collation versions ...")

databases = psql("-c", GET_COLLATION_VERSIONS)

warnings = []

for database in databases:
    db_name = database["datname"]
    if db_name in IGNORE:
        continue
    db_collation_version = database["datcollversion"]
    os_collation_version = database["oscollversion"]
    print(db_name)
    print(f"\tdb collation version: {db_collation_version}")
    print(f"\tos collation version: {os_collation_version}")
    if db_collation_version == os_collation_version:
        print("\tOK")
        continue

    affected_objects = list(psql("-c", GET_AFFECTED_OBJECTS, db_name))
    if not affected_objects:
        print("\tUpdating collation")
        psql(
            "-c",
            f"ALTER DATABASE {db_name} REFRESH COLLATION VERSION",
            db_name,
        )
    else:
        for row in affected_objects:
            obj, collation = row["Object"], row["Collation"]
            print(f"\tobject: {obj} collation: {collation}")
            warnings.append((db_name, obj, collation))
        # XXX create a warning for the agent so we can figure out what the
        # proper next step is See PL-131544 for context. potentially create
        # a maintenance item here

warning_file = pathlib.Path(DATADIR) / "postgresql-collation-warnings"

if warnings:
    with open(warning_file, "w") as f:
        for warning in warnings:
            f.write(str(warning))
else:
    warning_file.unlink(missing_ok=True)
