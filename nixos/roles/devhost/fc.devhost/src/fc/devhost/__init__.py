import argparse
import sys

from fc.devhost.manager import CONFIG_DIR, Manager


def main():
    a = argparse.ArgumentParser(
        prog="fc-devhost", description="Manage DevHost VMs."
    )
    a.set_defaults(func="print_usage")
    sub = a.add_subparsers(title="subcommands")

    def space_separated_list(str):
        if str == "":
            return []
        return str.split(" ")

    p = sub.add_parser("ensure", help="Create or update a given VM.")
    p.set_defaults(func="ensure")
    p.add_argument("--cpu", type=int, help="number of cores")
    p.add_argument("--memory", type=int, help="amount of memory")
    p.add_argument("--disk-size", type=str, help="disk size (e.g., 25G, 50G)")
    p.add_argument("--location", help="location the VMs live in")
    p.add_argument("--image-url", type=str, help="url to an image for the vm")
    p.add_argument(
        "--channel-url", type=str, help="url to the nix channel for the vm"
    )
    p.add_argument(
        "--hydra-eval",
        type=int,
        help="hydra eval to use for base image (deprecated, use --image-url and --channel-url)",
    )
    p.add_argument(
        "--aliases",
        type=space_separated_list,
        default=[],
        help="aliases for the nginx",
    )
    p.add_argument("name", help="name of the VM")

    # ---------------------------------

    p = sub.add_parser("destroy", aliases=["rm"], help="Destroy provided VMs.")
    p.set_defaults(func="destroy")
    p.add_argument(
        "name",
        nargs="+",
        help="name(s) of the VMs to be destroyed",
    )
    p.add_argument("--location", help="location the VMs live in")

    # ---------------------------------

    p = sub.add_parser(
        "list",
        aliases=["ls"],
        help="List VMs. By default all, can be limited by parameters.",
    )
    p.set_defaults(func="list_vms")
    p.add_argument("--user", type=str, help="user name creating the vm")
    p.add_argument(
        "-l",
        "--long-format",
        action="store_true",
        help="show more details of the vms",
    )
    p.add_argument("--location", help="location the VMs live in")

    # ---------------------------------

    p = sub.add_parser(
        "cleanup",
        help="Cleanup. This is an automated task. In this process old base images will be deleted.",
    )
    p.set_defaults(func="cleanup")
    p.add_argument("--location", help="location the VMs live in")

    # ---------------------------------

    p = sub.add_parser(
        "login",
        help="Login into the specified VM.",
    )
    p.set_defaults(func="login")
    p.add_argument("name", help="name of the VM")
    p.add_argument("--location", help="location the VMs live in")

    # ---------------------------------

    p = sub.add_parser(
        "shutdown",
        help="Shutdown the specified VM.",
    )
    p.set_defaults(func="shutdown")
    p.add_argument("name", help="name of the VM")
    p.add_argument("--location", help="location the VMs live in")

    # ---------------------------------

    args = a.parse_args()
    func = args.func

    if func == "print_usage":
        a.print_usage()
        sys.exit(1)

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    name = getattr(args, "name", None)
    kwargs = dict(args._get_kwargs())

    if func == "destroy":
        for name in args.name:
            manager = Manager(name)
            manager.destroy()

    del kwargs["func"]
    if "name" in kwargs:
        del kwargs["name"]

    manager = Manager(name)
    getattr(manager, func)(**kwargs)
