# copied from pkgs/fc/ceph/src/fc/ceph/__init__.py and modified

import configparser
import os
import sys


class VersionedSubsystem(object):
    """A marker base-class to indicate that a subsystem
    is versioned.

    Subclasses are expected to:

    1. be named properly after the subsystem they implement
       (to properly support config file entries)

    2. provide attributes based on the jewel releases they support

    """


class ConfigWithFallback(configparser.ConfigParser):
    """Wrapper class around ConfigParser whith advanced debug value fallback:
    While ConfigParser only fills up *existing* sections with default values if
    necessary, this wrapper also answers requests for non-existing sections with default
    data."""

    def __getitem__(self, section):
        try:
            return super().__getitem__(section)
        except KeyError:
            # if section does not exist, fall back to default section
            return super().__getitem__(self.default_section)


class Environment(object):
    """The environment manages environment variables (like PATH)
    and also allows to choose different subsystem implementations based on the
    Ceph release for each subsystem.

    We use this in a somewhat interesting factory-style that has side effects
    (by updating os.environ) to allow different subsystems to use different
    Ceph environments, mainly to simplify (slow) migration scenarios where
    multiple versions of Ceph are in use during a major upgrade.

    The main concepts managed are: different PATH variables depending on
    the system configuration as well as potentially choosing different
    subsystem implementations based on the Ceph release in use (so that the
    MONs could be running Luminous while the OSDs are still running Jewel
    on the same host.)

    """

    def __init__(self, config_file):
        self.config_file = config_file

    def prepare(self, subsystem, *args, **kwargs):
        """Prepare the environment and produce a usable subsystem instance.

        Normally we'd rely on the PATH being set by our environment. However,
        during migration scenarios we need to be able to manage OSDs, MONs and
        other calls to Ceph using different versions of Ceph.

        Different subsystems can be managed to access different Ceph binary
        environments (including different auxiliary tools like mkfs.xfs etc) in
        our config file:

        [default]
        path = ...
        release = jewel

        [KeyManager]
        path = ...

        [OSDManager]
        path = ...
        release = luminous

        """

        # Fix l18n so that we can count on output from external utilities.
        if "LC_ALL" in os.environ:
            del os.environ["LC_ALL"]
        os.environ["LANGUAGE"] = os.environ["LANG"] = "en_US.utf8"

        config = ConfigWithFallback(default_section="default")
        try:
            with open(self.config_file) as f:
                config.read_file(f)
        except FileNotFoundError as e:
            print("Error opening configuration file:", e, file=sys.stderr)
            sys.exit(1)

        # Set up PATH
        path = config[subsystem.__name__]["path"]
        os.environ["PATH"] = path

        # Choose subsystem implementation based on Ceph release
        if issubclass(subsystem, VersionedSubsystem):
            release = config[subsystem.__name__]["release"]
            subsystem = getattr(subsystem, release)

        return subsystem(*args, **kwargs)
