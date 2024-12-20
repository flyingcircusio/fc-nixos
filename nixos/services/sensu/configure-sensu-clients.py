#!/usr/bin/env python3.8

import asyncio
import multiprocessing
import sys
import textwrap
from pathlib import Path


class UserConfig:
    known_users: set
    user_db: list
    errors: list

    protected_users = set(["fc-sensu", "fc-telegraf", "sensu-server"])

    def __init__(self, known_users_file):
        self.errors = []
        self.known_users = set()
        for line in known_users_file.open():
            line = line.strip()
            if not line:
                continue
            if "[" not in line:
                # ignore headers:
                # Listing users ...
                # user      tags
                continue
            user = line.split("\t")[0]
            self.known_users.add(user)

        self.user_db = []
        self.users_to_delete = set(self.known_users)
        for line in Path("/var/lib/rabbitmq/sensu-clients").open():
            line = line.strip()
            if not line:
                continue
            nodename, user, password = line.split(":")
            self.user_db.append((nodename, user, password))
            if user in self.users_to_delete:
                self.users_to_delete.remove(user)

        self.users_to_delete = self.users_to_delete - self.protected_users
        print(f"{len(self.users_to_delete)} users to delete")
        print(f"{len(self.user_db)} users to configure")

    async def configure(self):
        self.max_jobs = asyncio.Semaphore(
            max([1, multiprocessing.cpu_count() - 1])
        )
        jobs = []
        for user in self.users_to_delete:
            jobs.append(self.delete_user(user))
        for nodename, user, password in self.user_db:
            jobs.append(self.configure_user(nodename, user, password))
        await asyncio.gather(*jobs, return_exceptions=True)
        return bool(self.errors)

    async def delete_user(self, user):
        async with self.max_jobs:
            print(f"Deleting {user}")
            await self.run(f"rabbitmqctl delete_user {user}")

    async def configure_user(self, nodename, user, password):
        async with self.max_jobs:
            if user not in self.known_users:
                print(f"Adding user {user} ...")
                await self.run(f"rabbitmqctl add_user {user} {password}")
                await self.run(
                    f"rabbitmqctl set_permissions -p /sensu {user} "
                    f"'((?!keepalives|results).)*' "
                    f"'^(keepalives|results|{nodename}.*)$' "
                    f"'((?!keepalives|results).)*'"
                )
            print(f"Updating user {user}")
            await self.run(f"rabbitmqctl change_password {user} {password}")

    async def run(self, cmd):
        proc = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        stdout, _ = await proc.communicate()
        stdout = stdout.decode("utf-8", errors="replace")
        if proc.returncode:
            self.errors.append((cmd, proc.returncode, stdout))
            print(f"`{cmd}` exited with error: {proc.returncode}")
            print(textwrap.indent(stdout, "   > ", lambda line: True))
            raise RuntimeError(stdout)


if __name__ == "__main__":
    config = UserConfig(Path(sys.argv[1]))
    sys.exit(asyncio.run(config.configure()))
