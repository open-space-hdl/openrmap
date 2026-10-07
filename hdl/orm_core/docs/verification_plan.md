# orm_core: Verification Plan

## 1. Overview

Two cores A and B are connected by a packet network model. The initiator of each core accesses the memory of the
other core; the commands of ECSS Annex A.4 and packets of other protocols are injected through the user port of the
sending core; the network corrupts, truncates or drops packets on request, or captures the packets of one direction
for a byte-by-byte comparison with the RMAP model of `tb/`. Memories are checked through the backdoor of the AXI memory
models, the register files through AXI4-Lite.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `orm_core_tb` | `orm_core_th` | Two `orm_core` at 100 MHz: A with a 32-bit and B with a 64-bit memory interface, logical addresses 0x20 and 0x30, tick 100 ns, timeout 20 us, `Transactions_g` = 1; per core an AXI memory model, the AXI4-Lite VVC, AXI4-Stream VVCs on the request data, the reply data and both directions of the user port, a monitor of the confirmations and indications; per network direction a fault model (flip of one data character, EEP instead of a data character, packet dropped) and a capture VVC |

VUnit configurations: `limited` (A initiator only, B target only) for TC-CO-05, `no_pass` (B without user port) for
TC-CO-06, `transactions8` (`Transactions_g` = 8) for TC-CO-09. Simulator: GHDL.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_annex_patterns` (TC-CO-01) | The four commands of ECSS Annex A.4 sent through the user port of A; the replies of B captured in the network equal the replies of Annex A.4; memory, indications and counters of B | CO-IF-01, CO-DM-01, CO-DM-05, CO-MX-01 |
| `test_write_read` (TC-CO-02) | Verified, non-verified, single-address and unacknowledged writes, reads and a read-modify-write from A to B while B writes to and reads from A; confirmations, read data, memories, counters of both register files | CO-IF-03, CO-DM-01, CO-MX-01, CO-NO-01 |
| `test_errors` (TC-CO-03) | Header CRC error in a command (timeout), Data CRC error and EEP in a verified write (status 4, 7, memory unchanged), Data CRC error in a read reply (data error), Header CRC error in a reply and lost reply (timeout), wrong key, Target Logical Address and address window (status 3, 12, 10); counters and event flags | CO-IF-03, CO-DM-01 |
| `test_passthrough` (TC-CO-04) | Packets of other protocols in both directions (other Protocol Identifiers, empty packet, one and two characters, extended protocol identifier ending with an EEP, 300 characters) interleaved with RMAP packets: every packet complete and unchanged at the user port of the other core | CO-IF-02, CO-DM-02, CO-DM-05, CO-MX-01 |
| `test_limited_nodes` (TC-CO-05) | Configuration `limited`: generics read back; write and read from A to B; reply sent to the target-only node B and command sent to the initiator-only node A discarded and counted; RMAP packets ending before the instruction at both nodes | CO-NO-01, CO-NO-02, CO-DM-01, CO-DM-03, CO-DM-04 |
| `test_no_passthrough` (TC-CO-06) | Configuration `no_pass`: generics read back; packets of other protocols (one, two and twelve characters) discarded and counted at B, RMAP traffic unaffected | CO-DM-02, CO-NO-02 |
| `test_mib` (TC-CO-07) | Single error injected into the write buffer of B through its register file: data corrected, SEC counted, interrupt; logical address, key and a read-only window configured through the register file and applied by the target | CO-IF-03 |
| `test_stress` (TC-CO-08) | Both initiators with 16 writes and 16 reads each, eight user packets in each direction, memories with 30 % backpressure | CO-IF-01, CO-IF-02, CO-IF-03, CO-MX-01 |
| `test_pipelined` (TC-CO-09) | Configuration `transactions8`: 24 writes and 24 reads of A with up to eight outstanding commands, memory of B with 30 % backpressure | CO-IF-03, CO-MX-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| CO-IF-01 | TC-CO-01, TC-CO-08 |
| CO-IF-02 | TC-CO-04, TC-CO-08 |
| CO-IF-03 | TC-CO-02, TC-CO-03, TC-CO-07 to TC-CO-09 |
| CO-DM-01 | TC-CO-01 to TC-CO-03, TC-CO-05 |
| CO-DM-02 | TC-CO-04, TC-CO-06 |
| CO-DM-03, CO-DM-04 | TC-CO-05 |
| CO-DM-05 | TC-CO-01, TC-CO-04 |
| CO-MX-01 | TC-CO-01, TC-CO-02, TC-CO-04, TC-CO-08, TC-CO-09 |
| CO-NO-01 | TC-CO-02, TC-CO-05 |
| CO-NO-02 | TC-CO-05, TC-CO-06 |
