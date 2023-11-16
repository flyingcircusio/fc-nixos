class FakeCmdStream:
    def __init__(self, content):
        self.content = content
        self.line_gen = (l for l in content.splitlines(keepends=True))

    def readline(self):
        try:
            return next(self.line_gen)
        except StopIteration:
            return ""

    def read(self):
        return self.content


class PollingFakePopen:
    def __init__(
        self, cmd, stdout="", stderr="", poll="stdout", returncode=0, pid=123
    ):
        self.cmd = cmd
        self.stdout = FakeCmdStream(stdout)
        self.stderr = FakeCmdStream(stderr)
        self.returncode = returncode
        self.pid = pid
        self._poll = poll

    def wait(self):
        pass
