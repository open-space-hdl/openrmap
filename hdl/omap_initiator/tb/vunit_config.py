# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the Initiator testbench: without transaction table."""


def configure(lib):
    tb = lib.test_bench("omap_initiator_tb")
    tb.test("test_no_table").add_config(name="no_table", generics={"Transactions_g": 0})
