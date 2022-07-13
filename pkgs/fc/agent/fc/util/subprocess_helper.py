"""Helpers for dealing with subprocesses"""


def get_popen_stdout_lines(popen, log=None, log_event=None):
    """Reads stdout line-by-line from a Popen object until the stream ends
    and returns a list of all received lines.
    Every line logged at trace level as it appears.

    WARNING: this is intended for (Nix) commands that return their main output
    on stdout and not much on stderr.

    Using it for a command that has a lot of output on stderr, too, may lead to
    deadlocks due to OS pipe buffers filling up! Use Popen.communicate() or
    something similar for such cases.
    """
    stdout_lines = []
    line = popen.stdout.readline()
    while line:
        if log is None:
            print(line, end="")
        else:
            log.trace(log_event, cmd_output_line=line.strip("\n"))
        stdout_lines.append(line)
        line = popen.stdout.readline()

    return stdout_lines


def get_popen_stderr_lines(popen, log, log_event):
    """Reads stderr line-by-line from a Popen object until the stream ends
    and returns a list of all received lines.
    Every line logged at trace level as it appears.

    WARNING: this is intended for (Nix) commands that return their main output
    on stderr and not much on stdout.

    Using it for a command that has a lot of output on stdout, too, may lead to
    deadlocks due to OS pipe buffers filling up! Use Popen.communicate() or
    something similar for such cases.
    """
    stderr_lines = []
    line = popen.stderr.readline()
    while line:
        log.trace(log_event, cmd_output_line=line.strip("\n"))
        stderr_lines.append(line)
        line = popen.stderr.readline()

    return stderr_lines
