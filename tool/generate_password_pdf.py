#!/usr/bin/env python3
"""Create the R3 RC4-128 PDF embedded (base64) in pdf_reader_native_test."""
import hashlib
import struct
from pathlib import Path


def rc4(key, data):
    s = list(range(256))
    j = 0
    for i in range(256):
        j = (j + s[i] + key[i % len(key)]) & 255
        s[i], s[j] = s[j], s[i]
    out = bytearray()
    i = j = 0
    for value in data:
        i = (i + 1) & 255
        j = (j + s[i]) & 255
        s[i], s[j] = s[j], s[i]
        out.append(value ^ s[(s[i] + s[j]) & 255])
    return bytes(out)


PAD = bytes.fromhex('28bf4e5e4e758a4164004e56fffa01082e2e00b6d0683e802f0ca9fe6453697a')


def key_rounds(value):
    value = hashlib.md5(value).digest()
    for _ in range(50):
        value = hashlib.md5(value).digest()
    return value[:16]


def encrypt_pdf():
    user = b'tylog'
    owner = b'tylog'
    permissions = -4
    file_id = hashlib.md5(b'tylog password fixture').digest()
    owner_key = key_rounds((owner + PAD)[:32])
    owner_entry = rc4(owner_key, PAD)
    for i in range(1, 20):
        owner_entry = rc4(bytes(value ^ i for value in owner_key), owner_entry)
    encryption_key = key_rounds((user + PAD)[:32] + owner_entry + struct.pack('<i', permissions) + file_id)
    user_entry = rc4(encryption_key, hashlib.md5(PAD + file_id).digest())
    for i in range(1, 20):
        user_entry = rc4(bytes(value ^ i for value in encryption_key), user_entry)
    user_entry += b'\0' * 16

    content = b'BT /F1 18 Tf 30 50 Td (Password research) Tj ET\n'
    encrypted_content = rc4(
        hashlib.md5(encryption_key + struct.pack('<I', 4)[:3] + b'\0\0').digest()[:16],
        content,
    )
    objects = [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 100] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
        b'<< /Length %d >>\nstream\n%s\nendstream' % (len(encrypted_content), encrypted_content),
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        b'<< /Filter /Standard /V 2 /Length 128 /R 3 /O <' + owner_entry.hex().encode() + b'> /U <' + user_entry.hex().encode() + b'> /P -4 >>',
    ]
    output = bytearray(b'%PDF-1.4\n')
    offsets = []
    for number, value in enumerate(objects, 1):
        offsets.append(len(output))
        output += f'{number} 0 obj\n'.encode()
        output += value + b'\nendobj\n'
    xref = len(output)
    output += f'xref\n0 {len(objects) + 1}\n0000000000 65535 f \n'.encode()
    output += b''.join(f'{offset:010d} 00000 n \n'.encode() for offset in offsets)
    output += (b'trailer\n<< /Size 7 /Root 1 0 R /Encrypt 6 0 R /ID [<' + file_id.hex().encode() + b'><' + file_id.hex().encode() + b'>] >>\nstartxref\n' + str(xref).encode() + b'\n%%EOF\n')
    return output


if __name__ == '__main__':
    target = Path(__file__).parent.parent / 'integration_test/fixtures/password-protected.pdf'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(encrypt_pdf())
