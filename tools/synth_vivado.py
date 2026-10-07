# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Out-of-context synthesis and implementation of orm_core with AMD Vivado for resources and timing.

Usage: python tools/synth_vivado.py [--part PART] [--link-mhz F] [--vivado PATH]
Writes vivado_out/synth.tcl, runs Vivado in batch mode and leaves the utilization and timing reports in
vivado_out/. LinkClk, UserClk and MgmtClk are independent clocks; the data and strobe inputs are asynchronous.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "vivado_out"
OLO_AREAS = ("base", "axi", "intf", "ft")


def sources():
    olo = []
    for line in (ROOT / "open-logic" / "compile_order.txt").read_text().splitlines():
        rel = line.strip()
        if rel and rel.split("/")[1] in OLO_AREAS:
            olo.append(ROOT / "open-logic" / rel)
    orm = []
    for line in (ROOT / "component_list.txt").read_text().splitlines():
        name = line.strip()
        if name and not name.startswith("#"):
            orm += sorted((ROOT / name / "src").glob("*.vhd"))
    return olo, orm


def tcl(part, link_mhz):
    olo, orm = sources()
    link_ns = 1000.0 / link_mhz
    lines = [f"read_vhdl -vhdl2008 -library olo {{{f.as_posix()}}}" for f in olo]
    lines += [f"read_vhdl -vhdl2008 -library openrmap {{{f.as_posix()}}}" for f in orm]
    lines += [
        f"synth_design -top orm_core -part {part} -mode out_of_context "
        f"-generic LinkClkFreq_g={link_mhz * 1e6:.1f}",
        f"create_clock -name LinkClk -period {link_ns:.3f} [get_ports LinkClk]",
        "create_clock -name UserClk -period 10.000 [get_ports UserClk]",
        "create_clock -name MgmtClk -period 10.000 [get_ports MgmtClk]",
        "set_clock_groups -asynchronous -group LinkClk -group UserClk -group MgmtClk",
        "set_false_path -from [get_ports {Spw_DIn Spw_SIn Rst}]",
        f"report_utilization -file {(OUT / 'utilization_synth.txt').as_posix()}",
        "opt_design",
        "place_design",
        "route_design",
        f"report_utilization -file {(OUT / 'utilization.txt').as_posix()}",
        f"report_utilization -hierarchical -hierarchical_depth 2 -file {(OUT / 'utilization_hier.txt').as_posix()}",
        f"report_timing_summary -file {(OUT / 'timing.txt').as_posix()}",
        "exit",
    ]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--part", default="xcvc1902-vsva2197-2MP-e-S")
    parser.add_argument("--link-mhz", type=float, default=200.0)
    parser.add_argument("--vivado", default=shutil.which("vivado") or r"D:\AMD\2025.2\Vivado\bin\vivado.bat")
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    script = OUT / "synth.tcl"
    script.write_text(tcl(args.part, args.link_mhz), encoding="utf-8")
    cmd = [args.vivado, "-mode", "batch", "-nojournal", "-log", str(OUT / "vivado.log"), "-source", str(script)]
    res = subprocess.run(cmd, cwd=OUT, stdin=subprocess.DEVNULL, env=os.environ)
    sys.exit(res.returncode)


if __name__ == "__main__":
    main()
