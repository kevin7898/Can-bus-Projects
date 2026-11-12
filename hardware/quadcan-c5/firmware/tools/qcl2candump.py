#!/usr/bin/env python3
"""Convert QuadCAN .qcl logs to candump (-L) text, CSV GPS tracks, or a quick summary.

  qcl2candump.py LOG.qcl                 -> candump -L lines on stdout (can0..can3)
  qcl2candump.py LOG.qcl --gps out.csv   -> also write GPS fixes (UBX-NAV-PVT) as CSV
  qcl2candump.py LOG.qcl --summary       -> per-channel counts, IDs, markers

candump -L output loads in SavvyCAN, python-can (can.CanutilsLogReader) and cantools.
"""
import argparse
import struct
import sys

HDR = struct.Struct("<IHHQ4I4IBB22s")
REC = struct.Struct("<QBBBBI")
F_EXT, F_RTR, F_FD, F_BRS, F_ESI, F_TX = 1, 2, 4, 8, 16, 32
TYPES = {1: "CAN", 2: "GPS", 3: "MARK", 4: "STATUS", 5: "ERROR"}


def records(path):
    with open(path, "rb") as f:
        raw = f.read()
    magic, ver, hlen, t0, *rest = HDR.unpack_from(raw, 0)
    if magic != 0x314C4351:
        raise SystemExit(f"{path}: not a QCL file")
    hdr = {"t0": t0, "bitrate": rest[0:4], "data_bitrate": rest[4:8], "cable": rest[8],
           "listen_mask": rest[9], "hw": rest[10].rstrip(b"\0").decode(errors="replace")}
    off = hlen
    out = []
    while off + REC.size <= len(raw):
        ts, typ, ch, flags, ln, ident = REC.unpack_from(raw, off)
        payload = raw[off + REC.size: off + REC.size + ln]
        if len(payload) < ln:
            break                       # truncated tail (power cut mid-write)
        out.append((ts, typ, ch, flags, ident, payload))
        off += (REC.size + ln + 3) & ~3
    return hdr, out


def candump_line(t0, ts, ch, flags, ident, data):
    t = (t0 + ts) / 1e6
    idtxt = f"{ident:08X}" if flags & F_EXT else f"{ident:03X}"
    if flags & F_FD:
        fd = (1 if flags & F_BRS else 0) | (2 if flags & F_ESI else 0)
        body = f"{idtxt}##{fd:X}{data.hex().upper()}"
    elif flags & F_RTR:
        body = f"{idtxt}#R"
    else:
        body = f"{idtxt}#{data.hex().upper()}"
    return f"({t:.6f}) can{ch} {body}"


def pvt(p):
    year, month, day, hour, minute, sec, valid = struct.unpack_from("<HBBBBBB", p, 4)
    fix, flags, _, nsv = struct.unpack_from("<BBBB", p, 20)
    lon, lat, h, hmsl = struct.unpack_from("<iiii", p, 24)
    gspeed, head = struct.unpack_from("<ii", p, 60)
    return (f"{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:{sec:02d}Z", fix, nsv,
            lat * 1e-7, lon * 1e-7, hmsl / 1000, gspeed / 1000, head * 1e-5)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--gps")
    ap.add_argument("--summary", action="store_true")
    a = ap.parse_args()
    hdr, recs = records(a.log)
    if a.summary:
        print(f"{a.log}: {hdr['hw']}, cable {hdr['cable']}, bitrates {hdr['bitrate']} fd {hdr['data_bitrate']}")
        for ch in range(4):
            ids = {r[4] for r in recs if r[1] == 1 and r[2] == ch}
            n = sum(1 for r in recs if r[1] == 1 and r[2] == ch)
            print(f"  CAN{ch + 1}: {n} frames, {len(ids)} IDs")
        for r in recs:
            if r[1] == 3:
                print(f"  MARK at {r[0] / 1e6:.3f}s {r[5].decode(errors='replace')}")
        print(f"  GPS fixes: {sum(1 for r in recs if r[1] == 2)}")
        return
    gps = open(a.gps, "w") if a.gps else None
    if gps:
        gps.write("t_s,utc,fix,sats,lat,lon,alt_m,speed_mps,heading_deg\n")
    w = sys.stdout.write
    for ts, typ, ch, flags, ident, data in recs:
        if typ == 1:
            w(candump_line(hdr["t0"], ts, ch, flags, ident, data) + "\n")
        elif typ == 2 and gps and len(data) >= 92:
            gps.write(f"{ts / 1e6:.3f}," + ",".join(str(v) for v in pvt(data)) + "\n")


if __name__ == "__main__":
    main()
