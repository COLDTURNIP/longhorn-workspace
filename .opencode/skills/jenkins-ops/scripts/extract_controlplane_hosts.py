#!/usr/bin/env python
"""Extract validated control-plane IP addresses from Jenkins console text."""

import ipaddress
import json
import re
import sys


IPV4_ASSIGNMENT = re.compile(r'^controlplane_public_ip = "(?P<address>[0-9.]+)"$')
IPV6_ASSIGNMENT = re.compile(r'^controlplane_public_ip = "\[(?P<address>[0-9A-Fa-f:]+)\]"$')


def main() -> int:
    if len(sys.argv) != 4:
        return 2

    console_path, job, build_text = sys.argv[1:]
    try:
        build = int(build_text)
        with open(console_path, "r", encoding="utf-8", errors="replace") as console:
            lines = console.read().splitlines()
    except (OSError, ValueError):
        return 1

    addresses = set()
    for line in lines:
        match = IPV4_ASSIGNMENT.fullmatch(line)
        address_type = ipaddress.IPv4Address
        if match is None:
            match = IPV6_ASSIGNMENT.fullmatch(line)
            address_type = ipaddress.IPv6Address
        if match is None:
            continue
        try:
            addresses.add(address_type(match.group("address")))
        except ipaddress.AddressValueError:
            continue

    hosts = [str(address) for address in sorted(addresses, key=lambda value: (value.version, int(value)))]
    json.dump({"build": build, "hosts": hosts, "job": job}, sys.stdout, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
