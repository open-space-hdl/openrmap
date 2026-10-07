# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Out-of-context synthesis and implementation of omap_core with AMD Vivado for resources and timing.

Usage: python tools/synth_vivado.py [--part PART] [--clk-mhz F] [--generic NAME=VALUE ...] [--vivado PATH]
Writes vivado_out/synth.tcl, runs Vivado in batch mode and leaves the utilization and timing reports in
vivado_out/. All ports are constrained to the single clock Clk.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "vivado_out"
OLO_AREAS = ("base", "axi", "ft")


def sources():
    olo = []
    for line in (ROOT / "open-logic" / "compile_order.txt").read_text().splitlines():
        rel = line.strip()
        if rel and rel.split("/")[1] in OLO_AREAS:
            olo.append(ROOT / "open-logic" / rel)
    omap = []
    for line in (ROOT / "component_list.txt").read_text().splitlines():
        name = line.strip()
        if name and not name.startswith("#"):
            files = sorted((ROOT / name / "src").glob("*.vhd"))
            # Packages first
            omap += [f for f in files if f.stem.endswith("_pkg")] + [f for f in files if not f.stem.endswith("_pkg")]
    return olo, omap


def tcl(part, clk_mhz, generics):
    olo, omap = sources()
    clk_ns = 1000.0 / clk_mhz
    gen = "".join(f" -generic {g}" for g in generics)
    lines = [f"read_vhdl -vhdl2008 -library olo {{{f.as_posix()}}}" for f in olo]
    lines += [f"read_vhdl -vhdl2008 -library openrmap {{{f.as_posix()}}}" for f in omap]
    lines += [
        f"synth_design -top omap_core -part {part} -mode out_of_context{gen}",
        f"create_clock -name Clk -period {clk_ns:.3f} [get_ports Clk]",
        f"set_input_delay -clock Clk {clk_ns / 2:.3f} [all_inputs]",
        f"set_output_delay -clock Clk {clk_ns / 2:.3f} [all_outputs]",
        f"report_utilization -file {(OUT / 'utilization_synth.txt').as_posix()}",
        "opt_design",
        "place_design",
        "route_design",
        f"report_utilization -file {(OUT / 'utilization.txt').as_posix()}",
        f"report_utilization -hierarchical -hierarchical_depth 3 -file {(OUT / 'utilization_hier.txt').as_posix()}",
        f"report_timing_summary -file {(OUT / 'timing.txt').as_posix()}",
        "exit",
    ]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--part", default="xcvc1902-vsva2197-2MP-e-S")
    parser.add_argument("--clk-mhz", type=float, default=200.0)
    parser.add_argument("--generic", action="append", default=[], help="generic of omap_core, NAME=VALUE")
    parser.add_argument("--vivado", default=shutil.which("vivado") or r"D:\AMD\2025.2\Vivado\bin\vivado.bat")
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    script = OUT / "synth.tcl"
    script.write_text(tcl(args.part, args.clk_mhz, args.generic), encoding="utf-8")
    cmd = [args.vivado, "-mode", "batch", "-nojournal", "-log", str(OUT / "vivado.log"), "-source", str(script)]
    res = subprocess.run(cmd, cwd=OUT, stdin=subprocess.DEVNULL, env=os.environ)
    sys.exit(res.returncode)


if __name__ == "__main__":
    main()
