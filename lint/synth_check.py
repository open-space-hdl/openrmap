"""Synthesis check of OpenRMAP with GHDL: elaborates and synthesises omap_core in the three node types and at the
values of its generics that the verification report lists (every value of the address width, the number of windows,
the Target SpaceWire Address length and the transaction table, every data width, the ends of the numeric ranges),
and checks that inconsistent configurations stop with the message of the core.

Usage: python lint/synth_check.py [-j N]
Uses the libraries compiled by the regression runner (run `python run.py --compile` first).
Exit code 0 when every configuration synthesises without error and without inferred latch, and every inconsistent
configuration fails with its message. This is a technology-independent check of synthesizability; resources and
timing need the FPGA tools.
"""

import argparse
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBS = ROOT / "vunit_out" / "ghdl" / "libraries"
NODE = {"Target_g": "true", "Initiator_g": "true", "Passthrough_g": "true"}


def configs():
    """Valid configurations: (generics, None); inconsistent ones: (generics, expected message)."""
    cfg = [({"Target_g": "true", "Initiator_g": "true", "Passthrough_g": "true"}, None),
           ({"Target_g": "true", "Initiator_g": "false", "Passthrough_g": "false"}, None),
           ({"Target_g": "false", "Initiator_g": "true", "Passthrough_g": "true"}, None),
           ({**NODE, "ExtAuth_g": "true"}, None)]
    cfg += [({**NODE, "AxiAddrWidth_g": str(a)}, None) for a in range(12, 41)]
    cfg += [({**NODE, "AxiAddrWidth_g": "12", "AxiDataWidth_g": "8"}, None),
            ({**NODE, "AxiAddrWidth_g": "40", "AxiDataWidth_g": "1024", "ChunkBytes_g": "128"}, None),
            ({**NODE, "AxiAddrWidth_g": "12", "BufferBytes_g": "4096", "ChunkBytes_g": "2048"}, None)]
    # Longest bursts: 4096 bytes, and at 12 address bits the largest command of the memory master
    cfg += [({**NODE, "AxiDataWidth_g": "1024", "AxiMaxBeats_g": "32", "ChunkBytes_g": "128"}, None),
            ({**NODE, "AxiAddrWidth_g": "12", "AxiDataWidth_g": "1024", "AxiMaxBeats_g": "8", "ChunkBytes_g": "128"},
             None),
            ({**NODE, "AxiAddrWidth_g": "12", "AxiMaxBeats_g": "256"}, None)]
    cfg += [({**NODE, "AxiDataWidth_g": str(2 ** w), "ChunkBytes_g": str(max(32, 2 ** w // 8))}, None)
            for w in range(3, 11)]
    cfg += [({**NODE, "AxiMaxBeats_g": str(b)}, None) for b in (1, 256)]
    # The ends of the chunk range are whole memory words only at 8-bit data
    cfg += [({**NODE, "AxiDataWidth_g": "8", "BufferBytes_g": "1", "ChunkBytes_g": "1"}, None),
            ({**NODE, "BufferBytes_g": "65535"}, None),
            ({**NODE, "AxiDataWidth_g": "8", "BufferBytes_g": "65535", "ChunkBytes_g": "65535"}, None)]
    cfg += [({**NODE, "Windows_g": str(w)}, None) for w in range(0, 9)]
    cfg += [({**NODE, "TgtAddrBytes_g": str(n)}, None) for n in range(0, 17)]
    cfg += [({**NODE, "Transactions_g": str(n)}, None) for n in range(0, 65)]
    cfg += [({**NODE, "TickCycles_g": str(v), "Timeout_g": str(v)}, None) for v in (0, 65535)]
    cfg += [({"Target_g": "false", "Initiator_g": "false"}, "Target_g or Initiator_g must be true"),
            ({**NODE, "AxiDataWidth_g": "24"}, "AxiDataWidth_g must be a power of 2"),
            ({**NODE, "BufferBytes_g": "64", "ChunkBytes_g": "128"}, "ChunkBytes_g must not be larger"),
            ({**NODE, "AxiDataWidth_g": "512"}, "ChunkBytes_g must be a multiple"),
            ({**NODE, "AxiDataWidth_g": "1024", "AxiMaxBeats_g": "33", "ChunkBytes_g": "128"},
             "AxiMaxBeats_g * AxiDataWidth_g/8 must not exceed"),
            ({**NODE, "AxiAddrWidth_g": "12", "AxiDataWidth_g": "1024", "ChunkBytes_g": "128"},
             "AxiMaxBeats_g * AxiDataWidth_g/8 must not exceed")]
    return cfg


def synth(generics, expected, out_dir):
    cmd = ["ghdl", "--synth", "--std=08", "-frelaxed", f"-P{LIBS / 'olo'}", "--work=openrmap",
           f"--workdir={LIBS / 'openrmap'}"]
    cmd += [f"-g{name}={value}" for name, value in generics.items()]
    cmd.append("omap_core")
    name = "omap_core" + "".join(f"_{k[:-2]}{v}" for k, v in generics.items() if k not in NODE or v != "true")
    with open(out_dir / f"{name}.vhd", "w") as netlist:
        res = subprocess.run(cmd, stdout=netlist, stderr=subprocess.PIPE, text=True)
    log = res.stderr
    if expected is not None:
        ok = res.returncode != 0 and expected in log
        return ok, f"{name}: {'rejected' if ok else 'NOT REJECTED as expected'}", []
    # Inferred latches are reported as "latch" warnings
    latches = [line for line in log.splitlines() if re.search(r"\blatch\b", line, re.IGNORECASE)]
    errors = [line for line in log.splitlines() if "error" in line.lower() or "exception" in line.lower()]
    ok = res.returncode == 0 and not latches and not errors
    return ok, f"{name}: {'OK' if ok else 'FAILED'}", (errors + latches)[:20]


def main():
    parser = argparse.ArgumentParser(description="GHDL synthesis check of omap_core")
    parser.add_argument("-j", type=int, default=1, help="parallel GHDL processes")
    args = parser.parse_args()
    if not LIBS.exists():
        raise SystemExit("compiled libraries not found, run: python run.py --compile")
    with tempfile.TemporaryDirectory() as tmp:
        with ThreadPoolExecutor(max_workers=args.j) as pool:
            results = list(pool.map(lambda c: synth(c[0], c[1], Path(tmp)), configs()))
    for ok, line, details in results:
        print(line)
        for detail in details:
            print("  " + detail)
    failed = sum(not ok for ok, _, _ in results)
    print(f"{len(results)} configurations, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
