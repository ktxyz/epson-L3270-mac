from epson_print.ipp import _read_response, _request, GROUP_JOB, TAG_CHARSET, PRINT_JOB


def test_print_job_encoding():
    body = _request(
        PRINT_JOB,
        7,
        [
            (TAG_CHARSET, "attributes-charset", "utf-8"),
        ],
        [(0x21, "copies", 2)],
    )
    assert body[0:4] == bytes([0x01, 0x01, 0x00, 0x02])
    assert GROUP_JOB in body


def test_response_parsing():
    body = bytearray([0x01, 0x01, 0x00, 0x00, 0, 0, 0, 1, 0x01])
    name = b"printer-state"
    body.extend([0x41, 0, len(name)])
    body.extend(name)
    body.extend([0, 1, ord("3")])
    body.append(0x03)
    status, attrs = _read_response(bytes(body))
    assert status == 0
    assert attrs["printer-state"] == ["3"]
