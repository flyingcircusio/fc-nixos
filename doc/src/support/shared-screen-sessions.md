---
global_sync_id: "v1"
---

# Shared screen sessions { #screen-multiuser }

The multiuser session feature of GNU `screen` comes handy if a user
needs remote assistance. Multiuser sessions allow other users to join in a
running screen session. They see the same terminal output as the inviting user
and are able to type in commands.

## Walk-through

We illustrate how to use it with an example. Imaging user `alice` has a screen
session running and wants to invite user `bob`.

We assume that `alice` is already running a screen session.

1. User `alice` needs to activate multiuser mode by typing
   ++Control-a :multiuser on<Return>++.
2. User `alice` needs to allow `bob` to join by typing ++Control-a :acladd    bob<Return>++.
3. User `bob` joins the screen session by invoking `screen -r    alice/` at the shell.
4. To detach from the shared session, bob types ++Control-a d++.

Both `alice` and `bob` should share the same terminal now. For further details,
please refer to the `screen(1)` manual page.

## Limitations

`screen` cannot be run inside `sudo` sessions. So start
screen first and then sudo inside the screen session.
