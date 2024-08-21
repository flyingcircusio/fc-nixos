import sys

data = """
LUKS header information
Version:        2
Epoch:          8
Metadata area:  16384 [bytes]
Keyslots area:  16744448 [bytes]
UUID:           25a97553-456d-424d-b753-0d9f4f6f928f
Label:          (no label)
Subsystem:      (no subsystem)
Flags:          (no flags)

Data segments:
  0: crypt
    offset: 16777216 [bytes]
    length: (whole device)
    cipher: aes-xts-plain64
    sector: 4096 [bytes]

Keyslots:
  0: luks2
    Key:        512 bits
    Priority:   normal
    Cipher:     aes-xts-plain64
    Cipher key: 512 bits
    PBKDF:      argon2id
    Time cost:  4
    Memory:     992242
    Threads:    4
    Salt:       44 42 a3 41 fd be f7 5f 71 ed 79 1e e5 ec a8 d6
                54 b0 71 04 57 db 8b 26 d5 ee 27 d7 0a e6 20 08
    AF stripes: 4000
    AF hash:    sha256
    Area offset:32768 [bytes]
    Area length:258048 [bytes]
    Digest ID:  0
  1: luks2
    Key:        512 bits
    Priority:   normal
    Cipher:     aes-xts-plain64
    Cipher key: 512 bits
    PBKDF:      argon2id
    Time cost:  4
    Memory:     983424
    Threads:    4
    Salt:       f1 23 25 d0 49 fe 58 7d 2e c4 c2 03 b9 ad 3b 91
                5e 6b 23 8e d6 2f d5 28 6e 0c 71 36 55 db 1c 8c
    AF stripes: 4000
    AF hash:    sha256
    Area offset:290816 [bytes]
    Area length:258048 [bytes]
    Digest ID:  0
Tokens:
Digests:
  0: pbkdf2
    Hash:       sha256
    Iterations: 77010
    Salt:       a1 96 76 95 83 07 61 84 32 86 33 88 21 0d c6 b9
                89 a3 f5 b6 19 a6 e6 07 6b 56 b2 0f 2a bd 3e 87
    Digest:     c5 11 30 cb 22 f3 e6 31 c1 c7 0c 38 c1 b8 67 bd
                34 75 6e 15 2d 26 30 7b e2 25 4a 66 62 9c ff e8
"""


# pbkdf: argon2id


def check_cipher(lines):
    for line in lines:
        line = line.strip()
        if not line.startswith("Cipher:"):
            continue
        cipher = line.split(":")[1].strip()
        if cipher != "aes-xts-plain64":
            yield f"cipher: {cipher} does not match aes-xts-plain64"


def extract_keyslot_numbers(lines):
    known_keyslots = set()
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
            header = int(header.strip())
        except Exception:
            continue
        assert value.strip() == "luks2", (header, value, line)
        known_keyslots.add(header)
    return known_keyslots


def check_key_slots_exactly_1_and_0(lines):
    keyslots = extract_keyslot_numbers(lines)
    if set([0, 1]) != keyslots:
        yield f"keyslots: unexpected configuration ({keyslots})"


def check_512_bit_keys(lines):
    for line in lines:
        line = line.strip()
        if not line.startswith("Key:"):
            continue
        key_size = line.split(":")[1].strip()
        if key_size != "512 bits":
            yield f"keysize: {key_size} does not match expected 512 bits"


def check_pbkdf_is_argon2id(lines):
    for line in lines:
        line = line.strip()
        if not line.startswith("PBKDF:"):
            continue
        pbkdf = line.split(":")[1].strip()
        if pbkdf != "argon2id":
            yield f"pbkdf: {pbkdf} does not match expected argon2id"


def main():
    checks = [
        check_cipher,
        check_key_slots_exactly_1_and_0,
        check_512_bit_keys,
        check_pbkdf_is_argon2id,
    ]
    lines = data.splitlines()
    errors = 0
    for check in checks:
        check_ok = True
        for error in check(lines):
            errors += 1
            check_ok = False
            print(f"{check.__name__}: {error}")
        if check_ok:
            print(f"{check.__name__}: OK")

    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
