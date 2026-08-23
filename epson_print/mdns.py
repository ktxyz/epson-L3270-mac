"""Discover IPP printers via mDNS (_ipp._tcp.local.)."""

from __future__ import annotations

import socket
import struct
import time
from dataclasses import dataclass


@dataclass
class Printer:
    name: str
    host: str
    port: int = 631
    resource: str = "/ipp/print"


def _decode_name(data: bytes, offset: int) -> tuple[str, int]:
    labels = []
    while True:
        length = data[offset]
        offset += 1
        if length == 0:
            break
        if length & 0xC0:
            ptr = struct.unpack_from(">H", data, offset - 1)[0] & 0x3FFF
            name, _ = _decode_name(data, ptr)
            labels.append(name)
            break
        labels.append(data[offset : offset + length].decode("utf-8", errors="replace"))
        offset += length
    return ".".join(labels), offset


def _parse_ptr_records(data: bytes) -> list[str]:
    names: list[str] = []
    pos = 12
    while pos < len(data):
        name, pos = _decode_name(data, pos)
        if pos + 10 > len(data):
            break
        rtype, _, _, rdlength = struct.unpack_from(">HHIH", data, pos)
        pos += 10
        rdata = data[pos : pos + rdlength]
        pos += rdlength
        if rtype == 12:  # PTR
            target, _ = _decode_name(rdata, 0)
            names.append(target.rstrip("."))
    return names


def find_printers(matching: str = "", timeout: float = 3.0) -> list[Printer]:
    """Browse for _ipp._tcp services; resolve host via getaddrinfo."""
    query = bytes.fromhex(
        "000001000001000000000000"
        "0569707020045f746370056c6f63616c00000c0001"
    )
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("", 5353))
    except OSError:
        pass
    sock.settimeout(0.5)
    deadline = time.time() + timeout
    seen: set[str] = set()
    while time.time() < deadline:
        try:
            sock.sendto(query, ("224.0.0.251", 5353))
            data, _ = sock.recvfrom(65535)
            for name in _parse_ptr_records(data):
                instance = name.split(".")[0]
                if matching and matching.lower() not in instance.lower():
                    continue
                if instance in seen:
                    continue
                seen.add(instance)
        except socket.timeout:
            continue
    sock.close()

    results: list[Printer] = []
    for instance in sorted(seen):
        host = instance
        if not host.endswith(".local"):
            host = f"{host}.local"
        try:
            infos = socket.getaddrinfo(host, 631, type=socket.SOCK_STREAM)
            for family, _, _, _, sockaddr in infos:
                if family == socket.AF_INET:
                    ip = sockaddr[0]
                    results.append(Printer(name=instance, host=ip))
                    break
            else:
                if infos:
                    results.append(Printer(name=instance, host=infos[0][4][0]))
        except socket.gaierror:
            continue
    return results
