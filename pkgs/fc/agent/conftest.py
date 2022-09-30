import pytest


def pytest_addoption(parser):
    parser.addoption(
        "--with-nix-build",
        action="store_true",
        default=False,
        dest="with_nix_build",
        help=(
            "Run tests that need a working Nix environment which can "
            "download and build things. Does not work in isolated environments"
        ),
    )


def pytest_collection_modifyitems(config, items):
    if config.getoption("with_nix_build"):
        return

    skip_nix = pytest.mark.skip(reason="needs --with-nix-build option to run")
    for item in items:
        if "needs_nix" in item.keywords:
            item.add_marker(skip_nix)
