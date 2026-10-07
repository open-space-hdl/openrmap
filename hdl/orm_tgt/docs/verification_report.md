# orm_tgt: Verification Report

## 1. Test results

Run on 2026-10-07 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*orm_tgt*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `orm_tgt_tb` | 20 (15 tests, TC-TG-01, 02, 03, 04, 14 in two configurations) | 20 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| The decoder kept the Data CRC register after a packet, so the Header CRC of the next command failed | The CRC register is cleared at the end of every packet |
| `olo_axi_master_full` with a user data width of 8 bits and an AXI data width of 32 bits wrote a beat with only one new byte for the second of two consecutive 4-byte commands; the following data lagged by bytes | TG-4 packs the bytes into AXI words itself and runs the master with the AXI data width on its user side |
| `olo_axi_master_simple` evaluates the read response only on the last beat of a burst; an error response of an earlier beat was not reported | TG-4 checks the response of every read beat on the AXI port |
