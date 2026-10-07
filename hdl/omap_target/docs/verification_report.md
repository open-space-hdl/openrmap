# omap_target: Verification Report

## 1. Test results

Run on 2026-10-07 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*omap_target*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `omap_target_tb` | 22 (16 tests, TC-TG-01, 02, 03, 04, 14, 16 in two configurations) | 22 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| The decoder kept the Data CRC register after a packet, so the Header CRC of the next command failed | The CRC register is cleared at the end of every packet |
| `olo_axi_master_full` with a user data width of 8 bits and an AXI data width of 32 bits wrote a beat with only one new byte for the second of two consecutive 4-byte commands; the following data lagged by bytes | TG-4 packs the bytes into AXI words itself and runs the master with the AXI data width on its user side |
| `olo_axi_master_simple` evaluates the read response only on the last beat of a burst; an error response of an earlier beat was not reported | TG-4 checks the response of every read beat on the AXI port |
| Code coverage: the status function of a completed write had branches for a header error and an external rejection, which end in Drain and never reach it | Branches removed (`writeEndStatus`) |
| Code coverage: no test for a rejected command with an EEP immediately after the header, for external rejections combined with early EOP, excess data and Data CRC error or without reply bit, for a reply requested while the encoder is busy, for a full write buffer, for an early EOP while committed chunks are still written, for single errors in the data of the AXI master, and for a reset in the middle of a command | Tests added to TC-TG-05, TC-TG-09, TC-TG-12, TC-TG-14 and TC-TG-15; TC-TG-16 added; all pass without design change |
| Code coverage: terms that cannot change a result: the single-address checks excluded read-modify-write commands, whose command code has the increment bit set; the status of an externally rejected command tested for read-modify-write, which is authorised in RmwExt_s; a double error in a discarded word set the buffer error of a command whose status is already an error | Terms removed |
