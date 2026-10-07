# orm_mib: Verification Plan

## 1. Overview

The MIB is verified through its AXI4-Lite port with the UVVM AXI4-Lite VVC: every register of the description is read
after reset, written and read back; the indications and events are driven by the sequencer and the configuration
outputs and the injection commands are observed. The harness can pulse two events in the cycle in which the register
file executes a write, to check that an event in the cycle of a clear is kept.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `orm_mib_tb` | `orm_mib_th` | `orm_mib` at 100 MHz with generics that differ from the defaults (`Windows_g` 4, `AxiDataWidth_g` 64, `BufferBytes_g` 512, `ChunkBytes_g` 64, `Passthrough_g` false, `ExtAuth_g` true, logical addresses 0x42 and 0x43, key 0x5A, tick 199, timeout 1000; window 0 open, window 1 read only at 0x12_0000_1000 to 0x12_0000_1FFF, window 5 open), AXI4-Lite VVC, observer |

Simulator: GHDL.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_reset_values` (TC-MB-01) | Every register after reset, generics, configuration from the generics, windows 0 and 1 from `WinInit_g`, windows 2 to 7 and unused addresses read zero, configuration outputs | MG-IF-01, MG-IF-02, MG-RF-01, MG-RF-02, MG-RF-03, MG-RF-07 |
| `test_config_registers` (TC-MB-02) | Write and read back of every RW register with unused bits set; the configuration outputs follow; every field of the four windows; the unused fourth word of a window reads zero; window 5 ignores writes; read-only registers ignore writes | MG-IF-01, MG-IF-02, MG-RF-01, MG-RF-02 |
| `test_target_status` (TC-MB-03) | Last command of the target; commands with status 0 per kind; every status code of ECSS 5.6 and an unknown one; replies, Header CRC errors, incomplete headers, replies received; event flags | MG-IF-02, MG-RF-04 |
| `test_initiator_status` (TC-MB-04) | Outstanding commands; every initiator event and every packet routing event counted; event flags of each source | MG-IF-02, MG-RF-04 |
| `test_flags_counters` (TC-MB-05) | Write one clears only the written flags; a write clears both counters of its register only; saturation at 0xFFFF; events in the cycle of a counter clear and of a flag clear kept | MG-RF-05 |
| `test_irq` (TC-MB-06) | Interrupt output and IRQ_STATUS for every flag alone, not for flags without enable | MG-RF-06, MG-IF-03 |
| `test_ecc` (TC-MB-07) | ECC events of the three channels counted per channel, DED flags, event flags, channel 3 reads zero, read and clear of a channel, global clear; injection commands per channel with single and double error, no injection without SINGLE and DOUBLE or into channel 3 | MG-ED-01, MG-ED-02 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| MG-IF-01 | TC-MB-01, TC-MB-02 |
| MG-IF-02 | TC-MB-01 to TC-MB-04 |
| MG-IF-03 | TC-MB-06 |
| MG-RF-01, MG-RF-02 | TC-MB-01, TC-MB-02 |
| MG-RF-03 | TC-MB-01 |
| MG-RF-04 | TC-MB-03, TC-MB-04 |
| MG-RF-05 | TC-MB-05 |
| MG-RF-06 | TC-MB-06 |
| MG-RF-07 | TC-MB-01 |
| MG-ED-01, MG-ED-02 | TC-MB-07 |
