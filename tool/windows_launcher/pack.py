#!/usr/bin/env python3
"""Bundle a Windows launcher with a payload zip into a single self-describing exe."""
import hashlib, os, struct, sys, tempfile

MAGIC = b"TYLOGPK1"


def pack(launcher_path, payload_path, version, out_path):
    launcher = open(launcher_path, "rb").read()
    payload = open(payload_path, "rb").read()
    ver = version.encode("utf-8")
    if len(ver) > 48:
        raise ValueError("version too long: %d bytes" % len(ver))
    footer = MAGIC + struct.pack("<Q", len(payload)) + ver.ljust(48, b"\0")
    assert len(footer) == 64
    blob = launcher + payload + footer
    with open(out_path, "wb") as f:
        f.write(blob)
    digest = hashlib.sha256(blob).hexdigest()
    with open(out_path + ".sha256", "w") as f:
        f.write(digest + "\n")  # bare hex, as the macOS .sha256 the updater reads
    print("wrote %s (%.2f MB)" % (out_path, len(blob) / (1024 * 1024)))
    print(digest)


def _self_test():
    tmp = tempfile.mkdtemp(prefix="tylog-pack-")
    launcher, payload = os.path.join(tmp, "mini.exe"), os.path.join(tmp, "mini.zip")
    out = os.path.join(tmp, "mini.bundle.exe")
    open(launcher, "wb").write(b"MZ" + b"\x00" * 10)
    open(payload, "wb").write(b"PK" + b"\x00" * 20)
    pack(launcher, payload, "0.0.0+1", out)
    footer = open(out, "rb").read()[-64:]
    assert footer[:8] == MAGIC, "bad magic"
    assert struct.unpack("<Q", footer[8:16])[0] == 22, "bad payload length"
    assert footer[16:].rstrip(b"\0").decode("utf-8") == "0.0.0+1", "bad version"
    print("self-test ok")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--self-test":
        _self_test()
    else:
        _, launcher, payload, version, out = sys.argv[:6]
        pack(launcher, payload, version, out)
