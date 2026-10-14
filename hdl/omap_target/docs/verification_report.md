# omap_target: Verification Report

## 1. Test results

Run on 2026-10-14 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*omap_target*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `omap_target_tb` | 37 (19 tests, TC-TG-01, 02, 03, 04, 16 in two configurations, TC-TG-14 and TC-TG-19 in three, TC-TG-18 in five, TC-TG-17 in six) | 37 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| The decoder kept the Data CRC register after a packet, so the Header CRC of the next command failed | The CRC register is cleared at the end of every packet |
| `olo_axi_master_full` with a user data width of 8 bits and an AXI data width of 32 bits wrote a beat with only one new byte for the second of two consecutive 4-byte commands; the following data lagged by bytes | Corrected in Open Logic (open-logic/open-logic#361, fork tag 4.7.0-ft.4). TG-4 runs the master with a user data width of 8 bits; TC-TG-02 writes 1 to 1000 bytes at unaligned addresses in consecutive commands |
| `olo_axi_master_simple` evaluated the read response only on the last beat of a burst, so an error response of an earlier beat was not reported, and kept the error of a failed last transaction for the next command | Corrected in Open Logic (open-logic/open-logic#362, fork tag 4.7.0-ft.4). TG-4 takes the memory errors from the master; TC-TG-11 reads across an error range whose error responses fall on middle beats of a burst |
| `olo_axi_master_simple` of Open Logic advanced the address of a command it splits into several transactions by the bytes of the transaction, computed in the width of its beat counter. With `AxiMaxBeats_g` smaller than `AxiDataWidth_g`/8 (32-bit bus with 1 to 3 beats, 64-bit bus with 1 to 7) the increment was zero, and every transaction of a split command accessed the words of the first transaction: reads returned its data again, writes overwrote its words, with an unaligned start also the bytes before the start address in the first word, and left the following addresses unwritten. The status reported success. Every OpenRMAP version before the move to Open Logic 4.7.0-ft.5 is affected; the tests ran with bursts of 16 beats only | Corrected in Open Logic (fork tag 4.7.0-ft.5). TC-TG-17 reads, writes and read-modify-writes at every start offset of a memory word with a 32-bit bus of 1 to 4 beats and a 64-bit bus of 7 and 8 beats. With fork tag 4.7.0-ft.4 it fails in every affected configuration, in the reads, in the writes and, with one beat, in the read-modify-writes across a word boundary, each at the first split access; the configurations with 4 and 8 beats pass |
| Code coverage: the status function of a completed write had branches for a header error and an external rejection, which end in Drain and never reach it | Branches removed (`writeEndStatus`) |
| Code coverage: no test for a rejected command with an EEP immediately after the header, for external rejections combined with early EOP, excess data and Data CRC error or without reply bit, for a reply requested while the encoder is busy, for a full write buffer, for an early EOP while committed chunks are still written, for single errors in the data of the AXI master, and for a reset in the middle of a command | Tests added to TC-TG-05, TC-TG-09, TC-TG-12, TC-TG-14 and TC-TG-15; TC-TG-16 added; all pass without design change |
| Code coverage: terms that cannot change a result: the single-address checks excluded read-modify-write commands, whose command code has the increment bit set; the status of an externally rejected command tested for read-modify-write, which is authorised in RmwExt_s; a double error in a discarded word set the buffer error of a command whose status is already an error | Terms removed |
| Non-verified write ended by an early EOP or an EEP right after a complete chunk, while the memory access block had not yet accepted the command of that chunk (slow memory, earlier chunks still written): the bytes of the chunk were discarded with the incomplete rest, the command never completed and the Target accepted no further command | Uncommitted bytes are discarded only when no command is pending; TC-TG-09 ends writes at chunk boundaries with a memory that stalls 90 % of the cycles |
| The controller lost the size of a write command that the memory access block accepted in the same cycle in which the controller passed it a byte of the previous command. While the memory access block packed the bytes into AXI words itself, it accepted a command only after all bytes of the previous one and the case did not occur; with the packing in the AXI master it does, and writes of several chunks stalled | The byte count includes the accepted command; TC-TG-02, TC-TG-09, TC-TG-11 and TC-TG-14 write several chunks back to back |
| GHDL runs before `run.py` gave every simulation its own `ghdl.sim_flags`: VUnit 5.0.0.dev7 appended the generics of a test to a list shared by the configurations of a test, so depending on the run order a configuration also ran with the generics of a configuration started before it, which it does not set itself (for example `int_auth` of TC-TG-16 with external authorisation, `windows4` of TC-TG-01 without windows, `chunk128` of TC-TG-14 with the 64-bit bus). QuestaSim was not affected | `run.py` copies the list per simulation and checks the generics of every GHDL command; all configurations pass in GHDL with their own generics |
| The memory access block (address, size, write word) and the command controller (header copy for the authorisation) left registers undefined after the reset that enter arithmetic and comparisons, in the block itself or in `olo_axi_master_full`: numeric_std metavalue warnings in simulation | The registers are reset (architecture D13); TC-CO-10 checks it at core level |
