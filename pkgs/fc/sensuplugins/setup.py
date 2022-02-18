"""Collection of FC-specific monitoring checks."""

from setuptools import setup

setup(
    name="fc.sensuplugins",
    version="1.0",
    description=__doc__,
    url="https://github.com/flyingcircus/nixpkgs",
    author="Flying Circus Internet Operations GmbH",
    author_email="mail@flyingcircus.io",
    license="ZPL",
    classifiers=["Programming Language :: Python :: 3.7"],
    packages=["fc.sensuplugins"],
    install_requires=["PyYAML", "nagiosplugin", "psutil", "requests"],
    entry_points={
        "console_scripts": [
            "check_disk=fc.sensuplugins.disk:main",
            "check_cpu_steal=fc.sensuplugins.cpu:main",
            "check_journal_file=fc.sensuplugins.journalfile:main",
            "check_lvm_integrity=fc.sensuplugins.lvm_integrity:main",
            "check_megaraid_cache=fc.sensuplugins.megaraid_cache:main",
            "check_swap_abs=fc.sensuplugins.swap:main",
            "check_writable=fc.sensuplugins.writable:main",
            "check_interfaces=fc.sensuplugins.interfaces:main",
            "check_psi=fc.sensuplugins.pressure_stall_information:main",
        ],
    },
)
