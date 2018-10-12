import argparse
import asyncio
import logging
import logging.handlers
import sys
import zlib

log = logging.getLogger(__name__)


queue = []


class GraphiteProtocoll:

    def __init__(self):
        self.known_hosts = set()

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, addr):
        # Graphite is line based. Split packet into lines. This way we can
        # estimate the byte size of the queue just by counting.
        items = data.split(b'\n')
        queue.extend(items)

        ip = addr[0]
        if ip not in self.known_hosts:
            self.known_hosts.add(ip)
            notice = log.info
        else:
            notice = log.debug
        notice('Received from %s (%d items, %d bytes).',
               ip, len(items), len(data))


@asyncio.coroutine
def submitter(loop, stats_host):
    reader, writer = yield from asyncio.open_connection(
        stats_host, 2004, loop=loop)
    compressor = zlib.compressobj()
    loops = 0
    submits = 0
    while True:
        yield from asyncio.sleep(1)

        exc = reader.exception()
        if exc:
            raise exc

        loops += 1
        log.debug('loops=%d queue=%d', loops, len(queue))
        if not queue or loops % 10 != 0 and len(queue) < 100:
            continue

        submits += 1
        # Every 10 seconds or at about 8k data (~80 bytes per queue entry)
        merged = b'\n'.join(sorted(queue))
        if submits < 10:
            notice = log.info
        elif submits == 10:
            log.info('Notifying only every 10 submits now.')
            notice = log.info
        elif submits % 10 == 0:
            notice = log.info
        else:
            notice = log.debug
        notice('Sending %d items (%d).', len(queue), submits)
        queue[:] = []
        writer.write(compressor.compress(merged))
        writer.write(compressor.flush(zlib.Z_SYNC_FLUSH))
        yield from writer.drain()


def parse_args():
    a = argparse.ArgumentParser()
    a.add_argument('-s', '--stats-host', help='stats host')
    a.add_argument('-l', '--listen', help='listen host')
    a.add_argument('-p', '--port', type=int, default=2003, help='listen port')
    a.add_argument('-d', '--debug', action='store_true', default=False)

    args = a.parse_args()
    return args


def main():
    args = parse_args()

    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(stream=sys.stdout, level=level)

    loop = asyncio.get_event_loop()
    log.info('Listening for graphite on %s:%d', args.listen, args.port)
    # One protocol instance will be created to serve all client requests
    listen = loop.create_datagram_endpoint(
        GraphiteProtocoll, local_addr=(args.listen, args.port))
    transport, protocol = loop.run_until_complete(listen)

    loop.run_until_complete(submitter(loop, args.stats_host))

    try:
        loop.run_forever()
    except KeyboardInterrupt:
        pass

    transport.close()
    loop.close()
