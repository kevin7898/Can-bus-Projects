"""Reader for DriveLine `frames.dlraw` raw CAN captures (format as observed Nov 2026).

Layout (little-endian):
    "DLRW" u16 version(1) u16 ?(1)
    repeated chunks:
        "CHNK" u32 payload_len u32 frame_count u32 crc u64 chunk_start_us u32 reserved
        payload_len bytes of records:
            varint dt        (delta from previous record in this chunk; see TICK_US)
            u8     flags     (always 0 so far)
            varint can_id
            u8     dlc
            dlc    data bytes

TICK_US: deltas inside a ~1 s chunk sum to ~2 s, and back-to-back 8-byte frames
at 500 kbit/s show deltas of ~490, which is ~245 us of bus time. So deltas are
treated as 0.5 us ticks. Either the board counts in half-microseconds or the
writer doubles them. Confirm against the logger source.
"""
import struct
import sys
from collections import defaultdict

TICK_US = 0.5


def _varint(b, j, end):
    v = s = 0
    while True:
        if j >= end:
            raise ValueError(f"truncated varint at {j}")
        c = b[j]
        j += 1
        v |= (c & 0x7F) << s
        s += 7
        if c < 0x80:
            return v, j


def frames(path, tick_us=TICK_US):
    """Yield (t_seconds, flags, can_id, data_bytes) for every record."""
    b = open(path, "rb").read()
    if b[:4] != b"DLRW":
        raise ValueError("not a DLRW file")
    i = 8
    while i < len(b):
        if b[i:i + 4] != b"CHNK":
            raise ValueError(f"bad chunk magic at {i}")
        if i + 28 > len(b):
            raise ValueError(f"truncated chunk header at {i}")
        ln, cnt, _crc, ts = struct.unpack_from("<IIIQ", b, i + 4)
        j, end, off, n = i + 28, i + 28 + ln, 0, 0
        if end > len(b):
            raise ValueError(
                f"chunk at {i}: payload needs {ln} bytes, file has {len(b) - j}")
        while j < end:
            dt, j = _varint(b, j, end)
            off += dt
            if j >= end:
                raise ValueError(f"chunk at {i}: truncated record at {j}")
            fl = b[j]
            j += 1
            cid, j = _varint(b, j, end)
            if j >= end:
                raise ValueError(f"chunk at {i}: truncated record at {j}")
            dlc = b[j]
            j += 1
            if j + dlc > end:
                raise ValueError(
                    f"chunk at {i}: frame 0x{cid:x} declares {dlc} bytes, "
                    f"{end - j} left")
            yield (ts + off * tick_us) / 1e6, fl, cid, b[j:j + dlc]
            j += dlc
            n += 1
        if j != end or n != cnt:
            raise ValueError(f"chunk at {i}: parsed {n}/{cnt} frames")
        i = end


def load(path, tick_us=TICK_US):
    """Return {can_id: (times ndarray[s], data ndarray[N,8] uint8)}."""
    import numpy as np

    T, D = defaultdict(list), defaultdict(list)
    for t, _fl, cid, d in frames(path, tick_us):
        T[cid].append(t)
        D[cid].append(bytes(d).ljust(8, b"\0"))
    return {
        k: (np.array(T[k]),
            np.frombuffer(b"".join(D[k]), dtype=np.uint8).reshape(-1, 8))
        for k in T
    }


if __name__ == "__main__":
    # Usage: python3 dlraw.py frames.dlraw  -> per-ID rate summary
    d = load(sys.argv[1])
    t0 = min(v[0][0] for v in d.values())
    t1 = max(v[0][-1] for v in d.values())
    dur = t1 - t0
    print(f"{sum(len(v[0]) for v in d.values())} frames, {dur:.1f} s")
    for cid in sorted(d):
        print(f"0x{cid:03x}  {len(d[cid][0]) / dur:7.1f} Hz  last {d[cid][1][-1].tobytes().hex(' ')}")
