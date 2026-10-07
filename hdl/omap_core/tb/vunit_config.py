# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the core testbench: an Initiator-only and a Target-only core, a core without user
port, eight outstanding commands."""


def configure(lib):
    tb = lib.test_bench("omap_core_tb")
    tb.test("test_limited_nodes").add_config(name="limited", generics={"TargetA_g": False, "InitiatorB_g": False})
    tb.test("test_no_passthrough").add_config(name="no_pass", generics={"PassB_g": False})
    tb.test("test_pipelined").add_config(name="transactions8", generics={"Transactions_g": 8})
