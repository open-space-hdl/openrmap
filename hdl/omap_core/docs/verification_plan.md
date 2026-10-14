# omap_core: Verification Plan

## 1. Overview

Two cores A and B are connected by a packet network model. The Initiator of each core accesses the memory of the
other core; the commands of ECSS Annex A.4 and packets of other protocols are injected through the user port of the
sending core; the network corrupts, truncates or drops packets on request, or captures the packets of one direction
for a byte-by-byte comparison with the RMAP model of `tb/`. Memories are checked through the backdoor of the AXI memory
models, the register files through AXI4-Lite.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `omap_core_tb` | `omap_core_th` | Two `omap_core` at 100 MHz: A with a 32-bit and B with a 64-bit memory interface, logical addresses 0x20 and 0x30, tick 100 ns, timeout 20 us, `Transactions_g` = 1; per core an AXI memory model, the AXI4-Lite VVC, AXI4-Stream VVCs on the request data, the reply data and both directions of the user port, a monitor of the confirmations and indications; per network direction a fault model (flip of one data character, EEP instead of a data character, packet dropped) and a capture VVC |

VUnit configurations: `limited` (A Initiator only, B Target only) for TC-CO-05, `no_pass` (B without user port) for
TC-CO-06, `transactions8` (`Transactions_g` = 8) for TC-CO-09, `ieee_warnings` (IEEE warnings enabled, post check of
the simulator output) for TC-CO-10. Simulator: GHDL.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_annex_patterns` (TC-CO-01) | The four commands of ECSS Annex A.4 sent through the user port of A; the replies of B captured in the network equal the replies of Annex A.4; memory, indications and counters of B | CO-IF-01, CO-DM-01, CO-DM-05, CO-MX-01 |
| `test_write_read` (TC-CO-02) | Verified, non-verified, single-address and unacknowledged writes, reads and a read-modify-write from A to B while B writes to and reads from A; confirmations, read data, memories, counters of both register files | CO-IF-03, CO-DM-01, CO-MX-01, CO-NO-01 |
| `test_errors` (TC-CO-03) | Header CRC error in a command (timeout), Data CRC error and EEP in a verified write (status 4, 7, memory unchanged), Data CRC error in a read reply (data error), Header CRC error in a reply and lost reply (timeout), wrong key, Target Logical Address and address window (status 3, 12, 10); counters and event flags | CO-IF-03, CO-DM-01 |
| `test_passthrough` (TC-CO-04) | Packets of other protocols in both directions (other Protocol Identifiers, empty packet, one and two characters, extended protocol identifier ending with an EEP, 300 characters) interleaved with RMAP packets: every packet complete and unchanged at the user port of the other core | CO-IF-02, CO-DM-02, CO-DM-05, CO-MX-01 |
| `test_limited_nodes` (TC-CO-05) | Configuration `limited`: generics read back; write and read from A to B; reply sent to the Target-only node B and command sent to the Initiator-only node A discarded and counted; RMAP packets ending before the instruction at both nodes | CO-NO-01, CO-NO-02, CO-DM-01, CO-DM-03, CO-DM-04 |
| `test_no_passthrough` (TC-CO-06) | Configuration `no_pass`: generics read back; packets of other protocols (one, two and twelve characters) discarded and counted at B, RMAP traffic unaffected | CO-DM-02, CO-NO-02 |
| `test_mib` (TC-CO-07) | Single error injected into the write buffer of B through its register file: data corrected, SEC counted, interrupt; logical address, key and a read-only window configured through the register file and applied by the Target | CO-IF-03 |
| `test_stress` (TC-CO-08) | Both Initiators with 16 writes and 16 reads each, eight user packets in each direction, memories with 30 % backpressure | CO-IF-01, CO-IF-02, CO-IF-03, CO-MX-01 |
| `test_pipelined` (TC-CO-09) | Configuration `transactions8`: 24 writes and 24 reads of A with up to eight outstanding commands, memory of B with 30 % backpressure | CO-IF-03, CO-MX-01 |
| `test_idle` (TC-CO-10) | Configuration `ieee_warnings`: after the reset the cores stay idle for 10 us; A is configured through its register file (identification, logical addresses, key, a window, timeout, interrupt enable, EDAC channel); both cores stay idle for 10 us; the first commands pass in both directions (writes with a partly filled last word, a verified write, reads, a read-modify-write) with a user packet in each direction; then B is configured. The post check fails on any numeric_std metavalue warning after the start marker and requires the warning of the testbench process `p_ieee_control` before it, which shows that the IEEE warnings are enabled. | CO-IF-03 |
| `test_timing` (TC-CO-11) | Writes and reads of 0 to 300 bytes from the Initiator of A to the Target of B: command taken by B, write reply taken by A, read request to confirmation; reads of 16 and 256 bytes and writes of 64 and 256 bytes back to back from the user port of A to the Target of B (period from 5 and 10 commands) | CO-PF-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| CO-IF-01 | TC-CO-01, TC-CO-08 |
| CO-IF-02 | TC-CO-04, TC-CO-08 |
| CO-IF-03 | TC-CO-02, TC-CO-03, TC-CO-07 to TC-CO-10 |
| CO-DM-01 | TC-CO-01 to TC-CO-03, TC-CO-05 |
| CO-DM-02 | TC-CO-04, TC-CO-06 |
| CO-DM-03, CO-DM-04 | TC-CO-05 |
| CO-DM-05 | TC-CO-01, TC-CO-04 |
| CO-MX-01 | TC-CO-01, TC-CO-02, TC-CO-04, TC-CO-08, TC-CO-09 |
| CO-NO-01 | TC-CO-02, TC-CO-05 |
| CO-NO-02 | TC-CO-05, TC-CO-06 |
| CO-NO-03 | TC-PKG-05 |
| CO-PF-01 | TC-CO-11 |
