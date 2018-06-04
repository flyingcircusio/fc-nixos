from setuptools import setup
from setuptools.command.test import test as TestCommand
from codecs import open
from os import path
import sys

here = path.abspath(path.dirname(__file__))

with open('README.txt', encoding='ascii') as f:
    long_description = f.read()

test_req = ['pytest']  # , 'pytest-catchlog', 'freezegun']


class PyTest(TestCommand):
    user_options = [('pytest-args=', 'a', "Arguments to pass to py.test")]

    def initialize_options(self):
        TestCommand.initialize_options(self)
        self.pytest_args = []

    def finalize_options(self):
        TestCommand.finalize_options(self)
        self.test_args = []
        self.test_suite = True

    def run_tests(self):
        # import here, cause outside the eggs aren't loaded
        import pytest
        errno = pytest.main(self.pytest_args)
        sys.exit(errno)


setup(
    name='collectdproxy',
    version='0.1',
    description=__doc__,
    long_description=long_description,
    url='https://XXXX',
    author='Christian Zagrodnick',
    author_email='cz@flyingcircus.io',
    license='ZPL',
    classifiers=[
        'Programming Language :: Python :: 3.4',
        'Programming Language :: Python :: 3.5',
    ],
    packages=['collectdproxy'],
    package_dir={'': 'src'},
    install_requires=[],
    tests_require=test_req,
    cmdclass={'test': PyTest},
    extras_require={
        'dev': test_req + ['pytest-cov'],
        'test': test_req,
    },
    zip_safe=False,
    entry_points={
        'console_scripts': [
            'statshost-proxy=collectdproxy.statshost:main',
            'location-proxy=collectdproxy.location:main',
        ],
    },
)
