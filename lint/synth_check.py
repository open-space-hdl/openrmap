# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Synthesis check of OpenRMAP with GHDL: elaborates orm_core as target and initiator, as target only and as
initiator only.

Usage: python lint/synth_check.py
Uses the libraries compiled by the regression runner (run `python run.py --compile` first).
Exit code 0 when every configuration synthesizes without error and without inferred latch.
This is a technology-independent check of synthesizability; resources and timing need the FPGA tools.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBS = ROOT / "vunit_out" / "ghdl" / "libraries"
CONFIGS = [("orm_core", {"Target_g": "true", "Initiator_g": "true", "Passthrough_g": "true"}),
           ("orm_core", {"Target_g": "true", "Initiator_g": "false", "Passthrough_g": "false"}),
           ("orm_core", {"Target_g": "false", "Initiator_g": "true", "Passthrough_g": "true"})]


def synth(top, generics, out_dir):
    cmd = ["ghdl", "--synth", "--std=08", "-frelaxed", f"-P{LIBS / 'olo'}", "--work=openrmap",
           f"--workdir={LIBS / 'openrmap'}"]
    cmd += [f"-g{name}={value}" for name, value in generics.items()]
    cmd.append(top)
    name = top + "".join(f"_{v}" for v in generics.values())
    with open(out_dir / f"{name}.vhd", "w") as netlist:
        res = subprocess.run(cmd, stdout=netlist, stderr=subprocess.PIPE, text=True)
    log = res.stderr
    # Inferred latches are reported as "latch" warnings
    latches = [line for line in log.splitlines() if re.search(r"\blatch\b", line, re.IGNORECASE)]
    errors = [line for line in log.splitlines() if "error" in line.lower() or "exception" in line.lower()]
    ok = res.returncode == 0 and not latches and not errors
    print(f"{name}: {'OK' if ok else 'FAILED'}")
    for line in (errors + latches)[:20]:
        print("  " + line)
    return ok


def main():
    if not LIBS.exists():
        raise SystemExit("compiled libraries not found, run: python run.py --compile")
    with tempfile.TemporaryDirectory() as tmp:
        results = [synth(top, gen, Path(tmp)) for top, gen in CONFIGS]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
