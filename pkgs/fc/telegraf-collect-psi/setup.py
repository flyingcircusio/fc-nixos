from setuptools import setup

setup(
    name="fc.collect_psi",
    version="1.0",
    description=__doc__,
    url="https://github.com/flyingcircus/nixpkgs",
    author="Flying Circus Internet Operations GmbH",
    author_email="mail@flyingcircus.io",
    license="ZPL",
    classifiers=[
        "Programming Language :: Python :: 3.7",
    ],
    packages=["collect_psi"],
    entry_points={
        "console_scripts": [
            "collect_psi=collect_psi.collect_psi:main",
            "collect_psi_cgroups=collect_psi.collect_psi_cgroups:main",
        ],
    },
)
