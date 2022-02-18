import argparse
import asyncio
import logging
import sys
import zlib

log = logging.getLogger(__name__)

MAX_LEN = 1400


@asyncio.coroutine
def handle_receive(reader, writer, sender):
    peername = writer.get_extra_info("peername")
    log.info("New connection from {}".format(peername))

    decompressor = zlib.decompressobj()

    remainder = b""
    to_submit = []
    submits = 0

    while True:
        data = yield from reader.read(MAX_LEN)
        if not data:
            break
        result = decompressor.decompress(data)
        lines = result.split(b"\n")
        log.debug(
            "Received %d lines (%d bytes) from %s",
            len(lines),
            len(data),
            peername,
        )
        if remainder:
            to_submit.append(remainder + lines.pop(0))
        if lines and lines[-1]:
            remainder = lines.pop()
        to_submit.extend(lines)

        bts = 0
        to_send = []
        while to_submit:
            if bts + len(to_submit[0]) < MAX_LEN:
                bts += len(to_submit[0])
                to_send.append(to_submit.pop(0))
            else:
                submits += 1

                send_string = b"\n".join(to_send + [b""])

                if submits < 10:
                    notice = log.info
                elif submits == 10:
                    log.info("Notifying only every 1000 submits now.")
                    notice = log.info
                elif submits % 1000 == 0:
                    notice = log.info
                else:
                    notice = log.debug
                notice(
                    "Sending %d items, %d bytes received from %s (%d).",
                    len(to_send),
                    len(send_string),
                    peername,
                    submits,
                )

                sender.sendto(send_string)
                to_send = []
                bts = 0

        to_submit[:] = []

    log.info("Disconnect from %s", peername)


def parse_args():
    a = argparse.ArgumentParser()
    a.add_argument(
        "-s",
        "--stats-host",
        help="stats host",
        default="stats.flyingcircus.io:2003",
    )
    a.add_argument("-d", "--debug", action="store_true", default=False)

    args = a.parse_args()
    return args


def main():
    args = parse_args()

    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(stream=sys.stdout, level=level)

    log.info("Submitting to %s", args.stats_host)
    stats_host = tuple(args.stats_host.split(":"))

    loop = asyncio.get_event_loop()

    connect = loop.create_datagram_endpoint(
        asyncio.DatagramProtocol, remote_addr=stats_host
    )
    sender, _ = loop.run_until_complete(connect)

    coro = asyncio.start_server(
        lambda r, w: handle_receive(r, w, sender), None, 2004
    )
    server = loop.run_until_complete(coro)

    # Serve requests until Ctrl+C is pressed
    log.info(
        "Serving on %s", ", ".join(str(s.getsockname()) for s in server.sockets)
    )
    try:
        loop.run_forever()
    except KeyboardInterrupt:
        pass

    # Close the server
    server.close()
    loop.run_until_complete(server.wait_closed())
    loop.close()
