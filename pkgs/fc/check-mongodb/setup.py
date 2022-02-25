from setuptools import setup

setup(
    packages=["fc.check_mongodb"],
    install_requires=[
        "pymongo",
    ],
    entry_points={
        "console_scripts": [
            "check_mongodb=fc.check_mongodb.mongodb:main",
        ],
    },
)
