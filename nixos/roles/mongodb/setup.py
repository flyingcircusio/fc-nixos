from setuptools import setup


setup(
    name='check_mongo',
    version='1.0',
    url='https://github.com/flyingcircus/nixpkgs',
    author='Maksim Bronsky',
    author_email='mb@flyingcircus.io',
    license='ZPL',
    classifiers=[
        'Programming Language :: Python :: 2.7',
    ],
    packages=['check_mongo'],
    install_requires=[''],
    entry_points={
        'console_scripts': [
            'check_mongo=check_mongo.check_mongodb:main',
        ],
    },
)
