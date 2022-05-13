import filecmp
import grp
import hashlib
import json
import os
import shutil
import socket
import tempfile

import structlog
from fc.util.directory import connect

structlog = structlog.get_logger()


def load_enc(log, enc_path):
    """Tries to read enc.json"""
    try:
        with open(enc_path) as f:
            enc = json.load(f)
    except (OSError, ValueError):
        # This environment doesn't seem to use an ENC,
        # i.e. containers. Silently ignore for now.
        log.info(
            "no-enc-data",
            msg="enc data not supported on this infrastructure, ignoring",
        )
        return {}

    return enc


def initialize_enc(log, tmpdir, enc_path):
    """Initialize ENC data during bootstrapping. Our automation puts an
    initial ENC file in /tmp which provides the password to allow the agent to
    talk to the directory and get updated ENC data from there."""
    if enc_path.exists():
        log.debug(
            "initialize-enc-present",
            _replace_msg=(
                "ENC file already present at {enc_path}, initialization not "
                "required."
            ),
            enc_path=str(enc_path),
        )
        return

    initial_enc_path = tmpdir / "fc-data/enc.json"
    if initial_enc_path.exists():
        log.info(
            "initialize-enc-init",
            _replace_msg=(
                "ENC file not found at {enc_path}, using initial data from "
                "{initial_enc_path}"
            ),
            enc_path=str(enc_path),
            initial_enc_path=str(initial_enc_path),
        )
        shutil.move(initial_enc_path, enc_path)
    else:
        log.info(
            "initialize-enc-initial-data-not-found",
            _replace_msg=(
                "ENC file not found at {enc_path} and initial data from "
                "{initial_enc_path} is also missing. Agent won't work!"
            ),
            enc_path=str(enc_path),
            initial_enc_path=str(initial_enc_path),
        )


def update_enc_nixos_config(log, enc, enc_path):
    """Update nixos config files managed through the enc."""
    basedir = os.path.join(os.path.dirname(enc_path), "enc-configs")
    if not os.path.isdir(basedir):
        os.makedirs(basedir)
    previous_files = set(os.listdir(basedir))
    sudo_srv = grp.getgrnam("sudo-srv").gr_gid
    for filename, config in enc["parameters"].get("nixos_configs", {}).items():
        log.info(
            "update-enc-nixos-config",
            filename=filename,
            content=hashlib.sha256(config.encode("utf-8")).hexdigest(),
        )
        target = os.path.join(basedir, filename)
        conditional_update(target, config, encode_json=False)
        os.chown(target, -1, sudo_srv)
        previous_files -= {filename}
    for filename in previous_files:
        log.info("remove-stale-enc-nixos-config", filename=filename)
        os.unlink(os.path.join(basedir, filename))


def conditional_update(filename, data, encode_json=True):
    """Updates JSON file on disk only if there is different content."""
    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".tmp",
        prefix=os.path.basename(filename),
        dir=os.path.dirname(filename),
        delete=False,
    ) as tf:
        if encode_json:
            json.dump(data, tf, ensure_ascii=False, indent=1, sort_keys=True)
        else:
            tf.write(data)
        tf.write("\n")
        os.chmod(tf.fileno(), 0o640)
    if not (os.path.exists(filename)) or not (filecmp.cmp(filename, tf.name)):
        with open(tf.name, "a") as f:
            os.fsync(f.fileno())
        os.rename(tf.name, filename)
    else:
        os.unlink(tf.name)


def inplace_update(filename, data):
    """Last-resort JSON update for added robustness.

    If there is no free disk space, `conditional_update` will fail
    because it is not able to create tempfiles. As an emergency measure,
    we fall back to rewriting the file in-place.
    """
    with open(filename, "r+") as f:
        f.seek(0)
        json.dump(data, f, ensure_ascii=False)
        f.flush()
        f.truncate()
        os.fsync(f.fileno())


def retrieve(log, directory_lookup, tgt):
    log.info("retrieve-enc", _replace_msg="Getting: {tgt}", tgt=tgt)
    try:
        data = directory_lookup()
    except Exception:
        log.error("retrieve-enc-failed", exc_info=True)
        return
    try:
        conditional_update("/etc/nixos/{}".format(tgt), data)
    except (IOError, OSError):
        inplace_update("/etc/nixos/{}".format(tgt), data)


def write_json(log, calls):
    """Writes JSON files from a list of (lambda, filename) pairs."""
    for call in calls:
        retrieve(log, *call)


def write_system_state(log):
    def load_system_state():
        result = {}
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        _, memkb, _ = line.split()
                        result["memory"] = int(memkb) // 1024
                        break
        except IOError:
            pass
        try:
            with open("/proc/cpuinfo") as f:
                cores = 0
                for line in f:
                    if line.startswith("processor"):
                        cores += 1
            result["cores"] = cores
        except IOError:
            pass
        return result

    write_json(
        log,
        [
            (lambda: load_system_state(), "system_state.json"),
        ],
    )


def update_inventory(log, enc):
    if (
        not enc
        or not enc.get("parameters")
        or not enc["parameters"].get("directory_password")
    ):
        log.warning(
            "update-inventory-no-pass",
            msg="No directory password. Not updating inventory.",
        )
        return
    try:
        # For fc-manage all nodes need to talk about *their* environment which
        # is resource-group specific and requires us to always talk to the
        # ring 1 API.
        directory = connect(enc, 1)
    except socket.error:
        log.warning(
            "update-inventory-no-connection",
            msg="No directory connection. Not updating inventory.",
        )
        return

    log.info(
        "update-inventory",
        _replace_msg="Getting inventory data from directory...",
    )

    write_json(
        log,
        [
            (lambda: directory.lookup_node(enc["name"]), "enc.json"),
            (
                lambda: directory.list_nodes_addresses(
                    enc["parameters"]["location"], "srv"
                ),
                "addresses_srv.json",
            ),
            (lambda: directory.list_permissions(), "permissions.json"),
            (lambda: directory.list_networks(), "networks.json"),
            (lambda: directory.list_service_clients(), "service_clients.json"),
            (lambda: directory.list_services(), "services.json"),
            (lambda: directory.list_users(), "users.json"),
            (lambda: directory.lookup_resourcegroup("admins"), "admins.json"),
        ],
    )


def update_enc(log, tmpdir, enc_path):
    """
    Gets ENC files from the directory, updates custom NixOS config from it
    and writes the current system state.
    """
    initialize_enc(log, tmpdir, enc_path)
    enc = load_enc(log, enc_path)
    update_inventory(log, enc)
    update_enc_nixos_config(log, enc, enc_path)
    write_system_state(log)
