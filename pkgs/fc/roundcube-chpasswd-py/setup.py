from setuptools import setup

setup(
    packages=["fc.roundcube_chpasswd"],
    entry_points={
        "console_scripts": [
            "roundcube-chpasswd=fc.roundcube_chpasswd.chpasswd:main",
        ],
    },
)
