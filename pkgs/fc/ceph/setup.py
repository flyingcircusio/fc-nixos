"""Collection of FC-specific ceph utilities."""

from setuptools import setup

setup(
    name="fc.ceph",
    version="1.0",
    description=__doc__,
    author="Flying Circus Internet Operations GmbH",
    author_email="mail@flyingcircus.io",
    license="ZPL",
    classifiers=["Programming Language :: Python :: 3"],
    packages=["fc.ceph", "fc.ceph.api"],
    entry_points={
        "console_scripts": [
            "fc-ceph=fc.ceph.main:main",
        ],
    },
)
