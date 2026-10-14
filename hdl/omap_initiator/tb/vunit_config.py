# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the Initiator testbench: without transaction table."""


def configure(lib):
    tb = lib.test_bench("omap_initiator_tb")
    tb.test("test_no_table").add_config(name="no_table", generics={"Transactions_g": 0})
    # Target SpaceWire Address length and transaction table at the ends of their ranges and in the middle
    for path, table in ((0, 0), (1, 1), (8, 8), (16, 64)):
        tb.test("test_sizes").add_config(name=f"path{path}_table{table}",
                                         generics={"TgtAddrBytes_g": path, "Transactions_g": table})
