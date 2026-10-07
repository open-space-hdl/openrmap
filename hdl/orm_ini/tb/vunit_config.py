# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the initiator testbench: without transaction table."""


def configure(lib):
    tb = lib.test_bench("orm_ini_tb")
    tb.test("test_no_table").add_config(name="no_table", generics={"Transactions_g": 0})
