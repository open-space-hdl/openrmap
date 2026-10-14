# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the Target testbench: external authorisation, a 64-bit memory bus, no address
windows, chunks of 128 bytes and short memory bursts."""


def configure(lib):
    tb = lib.test_bench("omap_target_tb")
    tb.test("test_ext_auth").add_config(name="ext_auth", generics={"ExtAuth_g": True})
    tb.test("test_reset").add_config(name="int_auth", generics={})
    tb.test("test_reset").add_config(name="ext_auth", generics={"ExtAuth_g": True})
    for name in ("test_write_variants", "test_read_variants", "test_rmw", "test_stress"):
        test = tb.test(name)
        test.add_config(name="axi32", generics={})
        test.add_config(name="axi64", generics={"AxiDataWidth_g": 64})
    # Every memory word width; chunks are whole words (64 and 128 bytes at 512 and 1024 bits), and single-address
    # writes of three 128-byte words need a larger verify buffer
    for name in ("test_write_variants", "test_read_variants", "test_rmw"):
        test = tb.test(name)
        for width in (8, 16, 128, 256, 512, 1024):
            test.add_config(name=f"axi{width}", generics={"AxiDataWidth_g": width, "BufferBytes_g": 512,
                                                          "ChunkBytes_g": max(32, width // 8)})
    # Chunks larger than a third of the data buffer of the AXI master: the buffer applies backpressure
    tb.test("test_stress").add_config(name="chunk128", generics={"ChunkBytes_g": 128})
    tb.test("test_annex_patterns").add_config(name="windows4", generics={})
    tb.test("test_annex_patterns").add_config(name="windows0", generics={"Windows_g": 0})
    # Bursts shorter than the memory word in bytes and the next lengths: the AXI master splits the commands into many
    # transactions. The 64-bit configurations use chunks of 128 bytes, so that also the writes are split
    for name, gen in (("axi32_beats1", {"AxiMaxBeats_g": 1}), ("axi32_beats2", {"AxiMaxBeats_g": 2}),
                      ("axi32_beats3", {"AxiMaxBeats_g": 3}), ("axi32_beats4", {"AxiMaxBeats_g": 4}),
                      ("axi64_beats7", {"AxiDataWidth_g": 64, "AxiMaxBeats_g": 7, "ChunkBytes_g": 128}),
                      ("axi64_beats8", {"AxiDataWidth_g": 64, "AxiMaxBeats_g": 8, "ChunkBytes_g": 128})):
        tb.test("test_burst_split").add_config(name=name, generics=gen)
    # Performance: memory rates with short and long bursts, chunks of 128 bytes and a 64-bit bus; command timing
    for name, gen in (("b16", {}), ("b1", {"AxiMaxBeats_g": 1}), ("b4", {"AxiMaxBeats_g": 4}),
                      ("c128", {"ChunkBytes_g": 128}), ("w64_b2", {"AxiDataWidth_g": 64, "AxiMaxBeats_g": 2})):
        tb.test("test_rate").add_config(name=name, generics=gen)
    for name, gen in (("axi32", {}), ("axi64", {"AxiDataWidth_g": 64}), ("c128", {"ChunkBytes_g": 128})):
        tb.test("test_timing").add_config(name=name, generics=gen)
    # Address width at the ends of its range and in the middle (the default configurations: 32 bits)
    # addr12_c2048: chunks longer than one command of the memory master (1020 bytes), so that the chunks are cut
    for name, gen in (("addr12", {"AxiAddrWidth_g": 12}), ("addr12_axi8", {"AxiAddrWidth_g": 12, "AxiDataWidth_g": 8}),
                      ("addr12_c2048", {"AxiAddrWidth_g": 12, "BufferBytes_g": 4096, "ChunkBytes_g": 2048}),
                      ("addr40", {"AxiAddrWidth_g": 40})):
        tb.test("test_addr_width").add_config(name=name, generics=gen)
    # Every number of address windows
    for windows in range(0, 9):
        tb.test("test_windows").add_config(name=f"windows{windows}", generics={"Windows_g": windows})
