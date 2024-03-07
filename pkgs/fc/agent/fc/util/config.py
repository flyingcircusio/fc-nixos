import configparser
from pathlib import Path


def parse_agent_config(log, config_file: Path):
    config = configparser.ConfigParser()
    if config_file:
        if config_file.is_file():
            log.debug(
                "parse-agent-config",
                config_file=config_file,
            )
            config.read(config_file)
        else:
            log.warn(
                "parse-agent-config-not-found",
                config_file=config_file,
            )

    return config
