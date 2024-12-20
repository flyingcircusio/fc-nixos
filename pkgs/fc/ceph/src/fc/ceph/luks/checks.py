from typing import Iterator

# In case these checks ever break: More recent cryptsetup versions also support
# JSON-formatted output via `cryptsetup luksDump --dump-json-metadata <dev>`.
# It most likely makes sense parsing that data instead once available.


def check_cipher(lines: str) -> Iterator[str]:
    checked = False  # plausibility check: did we get any cipher info?
    for line in lines:
        line = line.strip()
        if not line.startswith("Cipher:"):
            continue
        cipher = line.split(":")[1].strip()
        if cipher != "aes-xts-plain64":
            yield f"cipher: {cipher} does not match aes-xts-plain64"
        checked = True

    if not checked:
        yield "Unable to check cipher correctness, no `Cipher:` found in dump"


def _extract_keyslot_numbers(lines: str):
    known_keyslots: set[int] = set()
    lines_iter = iter(lines)
    for line in lines_iter:
        if line.startswith("Keyslots:"):
            break
    else:
        return known_keyslots

    for line in lines_iter:
        if line.startswith("Tokens:"):
            break
        if not ":" in line:
            continue
        header, value = line.split(":")
        try:
            header_i = int(header.strip())
        except Exception:
            continue
        assert value.strip() == "luks2", (header, value, line)
        known_keyslots.add(header_i)
    return known_keyslots


def check_key_slots_exactly_1_and_0(lines: str) -> Iterator[str]:
    keyslots = _extract_keyslot_numbers(lines)
    if set([0, 1]) != keyslots:
        yield f"keyslots: unexpected configuration ({keyslots})"


def check_512_bit_keys(lines: str) -> Iterator[str]:
    checked = False
    for line in lines:
        line = line.strip()
        if not line.startswith("Key:"):
            continue
        key_size = line.split(":")[1].strip()
        if key_size != "512 bits":
            yield f"keysize: {key_size} does not match expected 512 bits"
        checked = True

    if not checked:
        yield "Unable to check key size correctness, no `Key:` found in dump"


def check_pbkdf_is_argon2id(lines: str) -> Iterator[str]:
    checked = False
    for line in lines:
        line = line.strip()
        if not line.startswith("PBKDF:"):
            continue
        pbkdf = line.split(":")[1].strip()
        if pbkdf != "argon2id":
            yield f"pbkdf: {pbkdf} does not match expected argon2id"
        checked = True

    if not checked:
        yield "Unable to check PBKDF correctness, no `PBKDF:` found in dump"


# All these checks work on a list of lines output by `cryptsetup luksDump`
all_checks = [
    check_cipher,
    check_key_slots_exactly_1_and_0,
    check_512_bit_keys,
    check_pbkdf_is_argon2id,
]
