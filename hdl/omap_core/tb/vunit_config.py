# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the core testbench: an Initiator-only and a Target-only core, a core without user
port, eight outstanding commands, idle cores with the IEEE warnings enabled."""

import re
from pathlib import Path

IDLE_MARKER = "OMAP_IDLE_CHECK_START"

# Instance path of a simulator message: GHDL with --backtrace-severity=warning ("instance: <path>"), QuestaSim
# ("Process: <path>" or "Instance: <path>")
INSTANCE = re.compile(r"(?:instance|Instance|Process):\s*(\S+)")

# Positive control: the testbench process p_ieee_control converts an undefined vector before the marker
CONTROL = re.compile(r"^/omap_core_tb(/p_ieee_control)?$")


def metavalues(text, first, last):
    """Indices of the metavalue warnings in text[first:last]."""
    return [i for i in range(first, last) if "metavalue" in text[i].lower()]


def instance_of(text, i):
    """Instance path of the simulator message in line i, empty if the simulator printed none."""
    for line in text[i + 1:i + 3]:
        match = INSTANCE.search(line)
        if match:
            return match.group(1)
    return ""


def no_metavalue_after_marker(output_path):
    """Post check of test_idle: fails on a numeric_std metavalue warning after the marker of the testbench."""
    text = (Path(output_path) / "output.txt").read_text(encoding="utf-8", errors="replace").splitlines()
    start = next((i for i, line in enumerate(text) if IDLE_MARKER in line), None)
    if start is None:
        print("test_idle: marker " + IDLE_MARKER + " not found in the simulator output")
        return False
    if not any("TO_INTEGER" in text[i] and CONTROL.search(instance_of(text, i)) for i in metavalues(text, 0, start)):
        print("test_idle: no metavalue warning of p_ieee_control before the marker, the IEEE warnings are not enabled")
        return False
    found = [text[i] + " " + instance_of(text, i) for i in metavalues(text, start + 1, len(text))]
    print(f"test_idle: {len(found)} metavalue warnings after the marker")
    for line in found[:10]:
        print("test_idle: " + line)
    return not found


def configure(lib):
    tb = lib.test_bench("omap_core_tb")
    tb.test("test_limited_nodes").add_config(name="limited", generics={"TargetA_g": False, "InitiatorB_g": False})
    tb.test("test_no_passthrough").add_config(name="no_pass", generics={"PassB_g": False})
    tb.test("test_pipelined").add_config(name="transactions8", generics={"Transactions_g": 8})
    tb.test("test_idle").add_config(
        name="ieee_warnings",
        sim_options={"disable_ieee_warnings": False,
                     "ghdl.sim_flags": ["--max-stack-alloc=0", "--backtrace-severity=warning"]},
        post_check=no_metavalue_after_marker)
