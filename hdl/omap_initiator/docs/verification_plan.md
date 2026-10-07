# omap_initiator: Verification Plan

## 1. Overview

Every command sent by the Initiator is compared byte by byte with the command that the RMAP model of `tb/` builds from
the same fields, including the commands of ECSS Annex A.4. Replies built by the model, as they arrive after the
network removed the Reply SpaceWire Address, are injected intact and corrupted; the confirmations, the reply data and
the events are checked.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `omap_initiator_tb` | `omap_initiator_th` | `omap_initiator` at 100 MHz (`TgtAddrBytes_g` 8, `Transactions_g` 4, tick 100 ns), request descriptor driven by the sequencer, AXI4-Stream VVCs on the write data, the commands, the replies and the reply data, a monitor logging the confirmations and counting the events |

VUnit configuration `no_table` (`Transactions_g` = 0) for TC-IN-06. For TC-IN-08 the harness can drop the
characters of the data VVC and take and drop the commands. Simulator: GHDL.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_commands` (TC-IN-01) | The four commands of ECSS Annex A.4 (Target SpaceWire Address of 7 and 4 bytes, Reply Address of 7 bytes padded to 8 and of 4 bytes); all 16 command codes with Reply Addresses of 0 to 12 bytes, extended addresses and keys; zero-length verified write with Reply Address 0x00 | IN-IF-01, IN-IF-02, IN-TX-01, IN-TX-02, IN-TX-03 |
| `test_replies` (TC-IN-02) | Write, read, read-modify-write and zero-length read replies confirmed with their fields, read data passed on with `TLast`; error status codes confirmed | IN-IF-03, IN-RX-01, IN-RX-04, IN-TT-01 |
| `test_reply_errors` (TC-IN-03) | Header CRC error, incomplete header, EEP in the header, reserved bit, command bit, reply bit clear: no confirmation, counted; Data CRC error, short and long reply, EEP in the data and after the Data CRC, read reply ending after the Header CRC, write reply with excess data and with EEP: confirmation with data error, data stream terminated with `TLast` | IN-RX-02, IN-RX-03, IN-RX-04, IN-IF-04 |
| `test_table` (TC-IN-04) | Unknown Transaction Identifier and wrong instruction discarded as unexpected; request with a Transaction Identifier in use rejected, not sent, its data consumed, also with the rejection held by the user and the data arriving late; rejected read request; commands without reply not registered; full table holds the next request until a reply frees an entry | IN-TT-01, IN-TT-02, IN-IF-04 |
| `test_timeout` (TC-IN-05) | Timeout of 20 ticks: confirmation with timeout after 2 us, entry removed, late reply unexpected; reply in time: no timeout; confirmations held by the user: reply first, then the timeout, and no timeout of the command whose reply was held; a held timeout; timeout 0: no timeout | IN-TT-01, IN-TT-03 |
| `test_no_table` (TC-IN-06) | Without table: reply without command confirmed, same Transaction Identifier twice sent | IN-TT-04 |
| `test_reset` (TC-IN-08) | Reset in each of the first 80 cycles of a write with Target SpaceWire Address and data, of a rejected request held by the user and of a request waiting for a free entry; a write every 10 resets and a read with reply at the end are executed normally | IN-IF-05 |
| `test_stress` (TC-IN-07) | Random backpressure and gaps on all four streams, 30 writes and reads with replies interleaved, Reply Addresses of 0 to 8 bytes | IN-IF-01, IN-IF-02, IN-IF-03 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| IN-IF-01, IN-IF-02 | TC-IN-01, TC-IN-07 |
| IN-IF-03 | TC-IN-02, TC-IN-07 |
| IN-IF-04 | TC-IN-03, TC-IN-04 |
| IN-IF-05 | TC-IN-08 |
| IN-TX-01 to IN-TX-03 | TC-IN-01 |
| IN-RX-01 | TC-IN-02 |
| IN-RX-02, IN-RX-03 | TC-IN-03 |
| IN-RX-04 | TC-IN-02, TC-IN-03 |
| IN-TT-01 | TC-IN-02, TC-IN-04, TC-IN-05 |
| IN-TT-02 | TC-IN-04 |
| IN-TT-03 | TC-IN-05 |
| IN-TT-04 | TC-IN-06 |
