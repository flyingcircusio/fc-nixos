"""Collection of FC-specific ceph utilities."""

from setuptools import find_namespace_packages, setup

setup(
    name="fc.ceph",
    version="2.1",
    description=__doc__,
    author="Flying Circus Internet Operations GmbH",
    author_email="mail@flyingcircus.io",
    license="ZPL",
    classifiers=["Programming Language :: Python :: 3"],
    package_dir={"": "src"},
    packages=find_namespace_packages(where="src/"),
    entry_points={
        "console_scripts": [
            "fc-ceph=fc.ceph.main:main",
        ],
    },
)
