from setuptools import setup

setup(
    name="fc.check-haproxy",
    version="1.0",
    description=__doc__,
    url="https://github.com/flyingcircus/nixpkgs",
    author="Flying Circus Internet Operations GmbH",
    author_email="mail@flyingcircus.io",
    license="ZPL",
    classifiers=[
        "Programming Language :: Python :: 3.7",
    ],
    packages=["fc.check_haproxy"],
    install_requires=["nagiosplugin", "numpy"],
    entry_points={
        "console_scripts": [
            "check_haproxy=fc.check_haproxy.haproxy:main",
        ],
    },
)
