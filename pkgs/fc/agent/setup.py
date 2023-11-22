"""FC NixOS platform management utilities."""

from codecs import open
from os import path

from setuptools import setup

here = path.abspath(path.dirname(__file__))

# Get the long description from the README file
with open(path.join(here, "README.rst"), encoding="utf-8") as f:
    long_description = f.read()

test_deps = [
    "freezegun>=0.3",
    "responses",
    "pytest>=3",
    "pytest-mock",
    "pytest-structlog",
    "pytest-cov",
]

setup(
    name="fc.agent",
    version="1.0",
    description=__doc__,
    long_description=long_description,
    url="https://github.com/flyingcircusio/fc-nixos",
    author="Tobias Stenzel, Christian Kauhaus, Christian Theune",
    author_email="mail@flyingcircus.io",
    license="ZPL",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Environment :: Console",
        "License :: OSI Approved :: Zope Public License",
        "Programming Language :: Python :: 3.10",
        "Topic :: System :: Systems Administration",
    ],
    packages=[
        "fc.maintenance",
        "fc.maintenance.lib",
        "fc.maintenance.activity",
        "fc.manage",
        "fc.util",
    ],
    install_requires=[
        "PyYAML>=6",
        "click",
        "iso8601",
        "python-dateutil",
        "pytz",
        "requests",
        "rich",
        "shortuuid",
        "stamina",
        "structlog",
        "typer",
    ],
    zip_safe=False,
    setup_requires=["pytest-runner"],
    tests_require=test_deps,
    extras_require={"test": test_deps},
    entry_points={
        "console_scripts": [
            "fc-backy=fc.manage.backy:main",
            "fc-create-vm=fc.manage.createvm:main",
            "fc-directory=fc.util.directory:directory_cli",
            "fc-graylog=fc.manage.graylog:main",
            "fc-maintenance=fc.maintenance.cli:app",
            "fc-manage=fc.manage.cli:app",
            "fc-qemu-scrub=fc.manage.qemu:main",
            "fc-monitor=fc.manage.monitor:main",
            "fc-resize-disk=fc.manage.resize_disk:app",
            "fctl=fc.util.fctl:app",
        ],
    },
)
