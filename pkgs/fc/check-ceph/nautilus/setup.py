from setuptools import setup

setup(
    name="fc.check_ceph",
    version="1.0",
    description=__doc__,
    url="https://github.com/flyingcircus/nixpkgs",
    author="Flying Circus Internet Operations GmbH",
    author_email="mail@flyingcircus.io",
    license="ZPL",
    classifiers=[
        "Programming Language :: Python :: 3.7",
    ],
    packages=["fc.check_ceph"],
    install_requires=[
        "nagiosplugin",
    ],
    entry_points={
        "console_scripts": [
            "check_ceph=fc.check_ceph.ceph:main",
            "check_snapshot_restore_fill=fc.check_ceph.check_snapshot_restore:main",
        ],
    },
)
