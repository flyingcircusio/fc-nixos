"""Calculates Memory from dmidecode"""

import string
import subprocess


def get_paragraph(text):
    paragraph = []

    for line in text:
        line = line.strip()
        if not line:
            if paragraph:
                yield paragraph
                paragraph = []
        else:
            paragraph.append(line)
    if paragraph:
        yield paragraph


def get_device(entry):
    """Extract device info which is always represented as key-value"""
    params = [x.strip().split(':') for x in entry]
    # extract lines which consist exactly two elements
    return dict(x for x in params if len(x) == 2)


def calc_mem(modules):
    total = 0
    for m in modules:
        total += int(''.join(ch for ch in m['Size'] if ch in string.digits))
    return total


def main():
    modules = []
    dmidecode = subprocess.check_output(['dmidecode', '-q']).decode()
    for entry in get_paragraph(dmidecode.splitlines()):
        for line in entry:
            if 'Memory Device' in line:
                modules.append(get_device(entry))
    return calc_mem(modules)
