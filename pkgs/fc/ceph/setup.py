from setuptools import find_namespace_packages, setup

setup(
    package_dir={"": "src"},
    packages=find_namespace_packages(where="src/"),
)
