# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the Target testbench: external authorisation, a 64-bit memory bus and no address
windows."""


def configure(lib):
    tb = lib.test_bench("omap_target_tb")
    tb.test("test_ext_auth").add_config(name="ext_auth", generics={"ExtAuth_g": True})
    tb.test("test_reset").add_config(name="int_auth", generics={})
    tb.test("test_reset").add_config(name="ext_auth", generics={"ExtAuth_g": True})
    for name in ("test_write_variants", "test_read_variants", "test_rmw", "test_stress"):
        test = tb.test(name)
        test.add_config(name="axi32", generics={})
        test.add_config(name="axi64", generics={"AxiDataWidth_g": 64})
    tb.test("test_annex_patterns").add_config(name="windows4", generics={})
    tb.test("test_annex_patterns").add_config(name="windows0", generics={"Windows_g": 0})
