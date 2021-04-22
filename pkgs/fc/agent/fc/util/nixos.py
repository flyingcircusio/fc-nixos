"""Helpers for interaction with the NixOS system"""

import logging
import os
import os.path as p


def kernel_version(kernel):
    """Guesses kernel version from /run/*-system/kernel.

    Theory of operation: A link like `/run/current-system/kernel` points
    to a bzImage like `/nix/store/abc...-linux-4.4.27/bzImage`. The
    directory also contains a `lib/modules` dir which should have the
    kernel version as sole subdir, e.g.
    `/nix/store/abc...-linux-4.4.27/lib/modules/4.4.27`. This function
    returns that version number or bails out if the assumptions laid down here
    do not hold.
    """
    bzImage = os.readlink(kernel)
    moddir = os.listdir(p.join(p.dirname(bzImage), 'lib', 'modules'))
    if len(moddir) != 1:
        raise RuntimeError('modules subdir does not contain exactly '
                           'one item', moddir)
    return moddir[0]
