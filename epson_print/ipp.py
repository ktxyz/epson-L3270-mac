"""Minimal IPP/1.1 client over implicit TLS on port 631."""

from __future__ import annotations

import socket
import ssl
import struct

DEFAULT_PORT = 631

PRINT_JOB = 0x0002
GET_PRINTER_ATTRIBUTES = 0x000B
OK = 0x0000

TAG_INTEGER = 0x21
TAG_ENUM = 0x23
TAG_KEYWORD = 0x44
TAG_URI = 0x45
TAG_CHARSET = 0x47
TAG_NATLANG = 0x48
TAG_MIME = 0x49
TAG_NAME = 0x42
TAG_TEXT = 0x41

GROUP_OPERATION = 0x01
GROUP_JOB = 0x02
END_TAG = 0x03


def _attr(value_tag: int, name: str, value) -> bytes:
    if isinstance(value, str):
        value = value.encode("utf-8")
    elif isinstance(value, int):
        value = struct.pack(">i", value)
    name_b = name.encode("utf-8")
    return (
        struct.pack(">B", value_tag)
        + struct.pack(">H", len(name_b))
        + name_b
        + struct.pack(">H", len(value))
        + value
    )


def _request(operation: int, request_id: int, operation_attrs, job_attrs=()) -> bytes:
    out = bytearray()
    out += struct.pack(">HHIB", 0x0101, operation, request_id, GROUP_OPERATION)
    for tag, name, value in operation_attrs:
        out += _attr(tag, name, value)
    if job_attrs:
        out += struct.pack(">B", GROUP_JOB)
        for tag, name, value in job_attrs:
            out += _attr(tag, name, value)
    out += struct.pack(">B", END_TAG)
    return bytes(out)


def _read_response(response: bytes) -> tuple[int, dict]:
    if len(response) < 8:
        raise ValueError("IPP response too short")
    _, status, _, _ = struct.unpack_from(">HHIB", response, 0)
    attrs: dict[str, list] = {}
    name = None
    pos = 8
    while pos < len(response):
        tag = response[pos]
        pos += 1
        if tag == END_TAG:
            break
        if tag < 0x10:
            name = None
            continue
        name_len = struct.unpack_from(">H", response, pos)[0]
        pos += 2
        attr_name = response[pos : pos + name_len].decode("utf-8")
        pos += name_len
        value_len = struct.unpack_from(">H", response, pos)[0]
        pos += 2
        value = response[pos : pos + value_len]
        pos += value_len
        if attr_name:
            name = attr_name
        if name is None:
            continue
        if tag in (TAG_INTEGER, TAG_ENUM) and len(value) == 4:
            decoded = str(struct.unpack(">i", value)[0])
        else:
            decoded = value.decode("utf-8", errors="replace")
        attrs.setdefault(name, []).append(decoded)
    return status, attrs


def _http_post(host: str, port: int, resource: str, body: bytes, timeout: float) -> bytes:
    header = (
        f"POST {resource} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Content-Type: application/ipp\r\n"
        f"Content-Length: {len(body)}\r\n"
        f"Connection: close\r\n\r\n"
    ).encode("ascii") + body

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    addrs = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    addrs.sort(key=lambda a: 0 if a[0] == socket.AF_INET else 1)
    last_err: Exception | None = None
    for family, _, _, _, sockaddr in addrs:
        try:
            raw = socket.socket(family, socket.SOCK_STREAM)
            raw.settimeout(timeout)
            conn = ctx.wrap_socket(raw, server_hostname=host)
            conn.connect(sockaddr)
            conn.sendall(header)
            chunks: list[bytes] = []
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
            conn.close()
            raw_data = b"".join(chunks)
            sep = raw_data.find(b"\r\n\r\n")
            if sep < 0:
                raise ValueError("no HTTP header")
            return raw_data[sep + 4 :]
        except OSError as exc:
            last_err = exc
            continue
    raise ConnectionError(str(last_err or "connection failed"))


class IPPClient:
    def __init__(self, host: str, port: int = DEFAULT_PORT, resource: str = "/ipp/print"):
        self.host = host
        self.port = port
        self.resource = resource
        self._request_id = 0

    @property
    def uri(self) -> str:
        return f"ipp://{self.host}:{self.port}{self.resource}"

    def _next_id(self) -> int:
        self._request_id += 1
        return self._request_id

    def get_printer_attributes(self, timeout: float = 10) -> dict:
        body = _request(
            GET_PRINTER_ATTRIBUTES,
            self._next_id(),
            [
                (TAG_CHARSET, "attributes-charset", "utf-8"),
                (TAG_NATLANG, "attributes-natural-language", "en"),
                (TAG_URI, "printer-uri", self.uri),
                (TAG_NAME, "requesting-user-name", "epson-print"),
                (TAG_KEYWORD, "requested-attributes", "all"),
            ],
        )
        status, attrs = _read_response(_http_post(self.host, self.port, self.resource, body, timeout))
        if status != OK:
            raise RuntimeError(f"IPP error status 0x{status:04x}")
        return attrs

    def print_job(
        self,
        document: bytes,
        *,
        job_name: str = "epson-print",
        copies: int = 1,
        media: str | None = None,
        color_mode: str | None = None,
        quality: int | None = None,
        timeout: float = 120,
    ) -> dict:
        job_attrs = [(TAG_INTEGER, "copies", copies)]
        if media:
            job_attrs.append((TAG_KEYWORD, "media", media))
        if color_mode:
            job_attrs.append((TAG_KEYWORD, "print-color-mode", color_mode))
        if quality is not None:
            job_attrs.append((TAG_ENUM, "print-quality", quality))

        body = _request(
            PRINT_JOB,
            self._next_id(),
            [
                (TAG_CHARSET, "attributes-charset", "utf-8"),
                (TAG_NATLANG, "attributes-natural-language", "en"),
                (TAG_URI, "printer-uri", self.uri),
                (TAG_NAME, "requesting-user-name", "epson-print"),
                (TAG_NAME, "job-name", job_name),
                (TAG_MIME, "document-format", "image/pwg-raster"),
            ],
            job_attrs,
        )
        status, attrs = _read_response(
            _http_post(self.host, self.port, self.resource, body + document, timeout)
        )
        if status != OK:
            messages = attrs.get("status-message", []) + attrs.get("detailed-status-message", [])
            raise RuntimeError(f"printer rejected job 0x{status:04x}: {'; '.join(messages)}")
        return attrs
