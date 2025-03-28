#!/usr/bin/env python

# English Wiktionary:
#
#   "on tap": (of beer, etc) Available directly from the barrel, by
#   way of a tap.

import argparse

import scapy.all as scapy


class ArpIcmpMux_am(scapy.AnsweringMachine):
    """Auto-responder which handles both ARP and ethernet frames with
    ICMP echo-request packets.

    """

    def parse_options(self, **kwargs):
        self.arp_am = scapy.ARP_am(**kwargs)

    def is_request(self, req):
        if self.arp_am.is_request(req):
            return True
        elif req.haslayer(scapy.ICMP):
            icmp_req = req.getlayer(scapy.ICMP)
            if icmp_req.type == 8:  # echo-request
                return True

        return False

    def print_reply(self, req, reply):
        if self.arp_am.is_request(req):
            self.arp_am.print_reply(req, reply)
        else:
            print("Replying %s to %s" % (reply.getlayer(scapy.IP).dst, req.dst))

    def make_reply(self, req):
        if self.arp_am.is_request(req):
            return self.arp_am.make_reply(req)

        reply = (
            scapy.Ether(src=req[scapy.Ether].dst, dst=req[scapy.Ether].src)
            / scapy.IP(src=req[scapy.IP].dst, dst=req[scapy.IP].src)
            / scapy.ICMP()
            / scapy.Raw(load=req[scapy.Raw].load)
        )
        reply[scapy.ICMP].type = 0  # echo-reply
        reply[scapy.ICMP].seq = req[scapy.ICMP].seq
        reply[scapy.ICMP].id = req[scapy.ICMP].id
        reply[scapy.ICMP].unused = req[scapy.ICMP].unused
        # Force re-generation of the checksum
        reply[scapy.ICMP].chksum = None
        return reply


def gratuitous_arp(args):
    return scapy.Ether(src=args.mac, dst="ff:ff:ff:ff:ff:ff") / scapy.ARP(
        op="who-has", psrc=args.ip, pdst=args.ip
    )
    pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Respond to arp and ping on a tap interface"
    )

    parser.add_argument(
        "interface",
        metavar="INTERFACE",
        help="Tap interface to listen on (must already exist and be configured)",
    )
    parser.add_argument(
        "mac",
        metavar="MAC",
        help="MAC address to respond to on the tap interface",
    )
    parser.add_argument(
        "ip",
        metavar="IP",
        help="IPv4 address to respond to ICMP echo requests on the tap interface",
    )

    args = parser.parse_args()

    tap = scapy.TunTapInterface(args.interface, mode_tun=False)

    # send gratutous arp, so the host system's bridge interface learns
    # which bridge port we're on.
    pkt = gratuitous_arp(args)
    for i in range(5):
        tap.send(pkt)

    responder = tap.am(ArpIcmpMux_am, IP_addr=args.ip, ARP_addr=args.mac)

    # run infinitely until killed by signal
    responder(store=False)
