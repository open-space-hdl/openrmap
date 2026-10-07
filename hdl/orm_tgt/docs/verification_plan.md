# orm_tgt: Verification Plan

## 1. Overview

The target is verified through its ports: commands built by the RMAP model of `tb/` enter the command stream, the
replies are compared byte by byte with the replies built by the same model, and the memory is compared through the
backdoor of the AXI memory model. The CRC test patterns of ECSS Annex A.4 are part of the tests.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `orm_tgt_tb` | `orm_tgt_th` | `orm_tgt` at 100 MHz (AXI address width 32, `BufferBytes_g` 256, `ChunkBytes_g` 32), AXI4-Stream VVCs on the command and reply streams, AXI memory model instance 0, a responder on the external authorisation port, monitors of the indications and events |

VUnit configurations: `windows4` and `windows0` (four and no address windows) for TC-TG-01; `axi32` and `axi64`
(AXI data width 32 and 64, memory word of 4 and 8 bytes) for TC-TG-02, 03, 04 and 14; `ext_auth` (`ExtAuth_g`) for
TC-TG-12. All other tests run with four windows, a 32-bit AXI bus and no external authorisation. Simulator: GHDL.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_annex_patterns` (TC-TG-01) | The four commands of ECSS Annex A.4 give the replies of Annex A.4 (with and without Reply Address) and write and read the memory; indication fields | TG-IF-01, TG-IF-02, TG-IF-05, TG-RX-01, TG-RX-02, TG-RX-05, TG-TX-01, TG-TX-03, TG-TX-04 |
| `test_write_variants` (TC-TG-02) | All eight write commands: incrementing writes of 1 to 1000 bytes at unaligned addresses (verified up to the buffer size), exactly the addressed bytes written; single-address writes of three words to the same word; zero-length writes write nothing; reply only with the reply bit | TG-EX-01, TG-EX-02, TG-EX-03, TG-EX-07, TG-TX-01 |
| `test_read_variants` (TC-TG-03) | Incrementing reads of 0 to 1000 bytes at unaligned addresses, Reply Address Length 3, single-address read of three words | TG-EX-04, TG-EX-07, TG-TX-04 |
| `test_rmw` (TC-TG-04) | Read-modify-write of 1 to 4 bytes (across a word boundary), result (mask and data) or (not mask and read data), reply with the data read, example of ECSS Figure 5-16, zero bytes without memory access | TG-EX-05, TG-EX-07, TG-TX-04 |
| `test_header_errors` (TC-TG-05) | Header CRC errors, packets ending in the header with EOP or EEP at every position, EEP immediately after the header of a write, a read and a read-modify-write, a reply at the target, reserved packet types, Protocol Identifier 2: no reply, no memory access, events counted | TG-RX-02, TG-RX-03, TG-RX-04, TG-RX-06, TG-AU-01 |
| `test_invalid_codes` (TC-TG-06) | Command codes 0b0000, 0b0001, 0b0100, 0b0101 (no reply) and 0b0110 (reply): status 2 | TG-AU-02 |
| `test_authorisation` (TC-TG-07) | Logical addresses 0x42, 0x43 and 0xFE enabled and disabled, key check enabled and disabled, four windows with different permissions (bounds, crossing a bound, read, write, verified-only, read-modify-write, single address), alignment of single-address accesses, AXI address range, read-modify-write lengths 3 and 10, verified write of 257 bytes, priorities of the status codes; no memory access when rejected | TG-IF-03, TG-AU-03 to TG-AU-08 |
| `test_verified_errors` (TC-TG-08) | Verified write with Data CRC error, early EOP, excess data, EEP after the Data CRC and in the data, EEP and Data CRC error together, without reply: no byte written | TG-EX-01, TG-AU-08 |
| `test_unverified_errors` (TC-TG-09) | Non-verified write: Data CRC error after the data is written; early EOP and EEP: only complete chunks written; excess data: Data Length bytes written; a short write whose last byte is the Data CRC writes nothing | TG-EX-02 |
| `test_read_rmw_end_errors` (TC-TG-10) | Data after a read header (status 6) and with an EEP (status 7) without execution; read-modify-write with Data CRC error, early EOP, excess data and EEP without memory access | TG-EX-04, TG-EX-05, TG-RX-05 |
| `test_memory_errors` (TC-TG-11) | Error responses: non-verified and verified write status 1, read reply ended with an EEP after the data, read-modify-write read error (status 1, no data, nothing written) and write error (status 1, data read returned), normal operation afterwards | TG-EX-06 |
| `test_ext_auth` (TC-TG-12) | External authorisation: request fields, accepted and rejected write, read and read-modify-write, EEP before the rejection, no request for a read-modify-write with a Data CRC error | TG-IF-04, TG-EX-05, TG-AU-08 |
| `test_reply_address` (TC-TG-13) | Reply Address fields of ECSS Table 5-3 (all zero, internal and trailing zeros), 8 and 12 bytes | TG-TX-02 |
| `test_stress` (TC-TG-14) | 40 % random backpressure of the AXI memory, random gaps on the command stream and random backpressure on the reply stream: 4 kB write across a 4 kB boundary and read back, 40 commands of all kinds back to back | TG-IF-01, TG-IF-02, TG-EX-02, TG-EX-04 |
| `test_ecc` (TC-TG-15) | Single error in the write buffer corrected and counted; double errors in the write buffer and in the write data of the master give status 1, in the read data of the master an EEP after the data | TG-EX-06 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| TG-IF-01, TG-IF-02 | TC-TG-01, TC-TG-14 |
| TG-IF-03 | TC-TG-07 |
| TG-IF-04 | TC-TG-12 |
| TG-IF-05 | TC-TG-01 |
| TG-RX-01 | TC-TG-01 |
| TG-RX-02 | TC-TG-01, TC-TG-05 |
| TG-RX-03, TG-RX-04, TG-RX-06 | TC-TG-05 |
| TG-RX-05 | TC-TG-01, TC-TG-10 |
| TG-AU-01 | TC-TG-05 |
| TG-AU-02 | TC-TG-06 |
| TG-AU-03 to TG-AU-07 | TC-TG-07 |
| TG-AU-08 | TC-TG-07, TC-TG-08, TC-TG-12 |
| TG-EX-01 | TC-TG-02, TC-TG-08 |
| TG-EX-02 | TC-TG-02, TC-TG-09, TC-TG-14 |
| TG-EX-03 | TC-TG-02 |
| TG-EX-04 | TC-TG-03, TC-TG-10, TC-TG-14 |
| TG-EX-05 | TC-TG-04, TC-TG-10, TC-TG-12 |
| TG-EX-06 | TC-TG-11, TC-TG-15 |
| TG-EX-07 | TC-TG-02, TC-TG-03, TC-TG-04 |
| TG-TX-01 | TC-TG-01, TC-TG-02 |
| TG-TX-02 | TC-TG-13 |
| TG-TX-03 | TC-TG-01 |
| TG-TX-04 | TC-TG-01, TC-TG-03, TC-TG-04 |

## 5. Negative tests

| Fault | Test cases |
| --- | --- |
| Header CRC error, incomplete header, EEP after the header | TC-TG-05 |
| Reserved packet type, reply at the target, other Protocol Identifier, invalid command code | TC-TG-05, TC-TG-06 |
| Wrong logical address, key, window, permission, alignment, length | TC-TG-07 |
| Data CRC error, early EOP, excess data, EEP in the data | TC-TG-08, TC-TG-09, TC-TG-10 |
| Memory error responses | TC-TG-11 |
| Rejection by the external authorisation | TC-TG-12 |
| Single and double errors in the data buffers | TC-TG-15 |
