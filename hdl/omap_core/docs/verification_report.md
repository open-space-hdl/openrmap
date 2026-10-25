# omap_core: Verification Report

## 1. Test results

Run on 2026-10-25 with GHDL 6.0.0 (mcode) and QuestaSim (without and with code coverage, time resolution 1 fs),
VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*omap_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `omap_core_tb` | 11 (TC-CO-05 in `limited`, TC-CO-06 in `no_pass`, TC-CO-09 in `transactions8`, TC-CO-10 in `ieee_warnings`) | 11 |

## 2. Generics

Values of the generics of `omap_core` that are simulated (in the testbench of the core or of the module that uses the
generic) and synthesised with GHDL by `lint/synth_check.py`. The check also confirms that the inconsistent
configurations stop the elaboration with the message of the core (CO-NO-03).

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `Target_g`, `Initiator_g` | boolean, not both false | Target and Initiator, Target only, Initiator only (TC-CO-05) | the three node types; both false rejected |
| `Passthrough_g` | boolean | both (TC-CO-06) | both |
| `AxiAddrWidth_g` | 12 to 40 | 12, 32, 40 (TC-TG-20; all other tests at 32) | every value |
| `AxiDataWidth_g` | 8 to 1024, power of 2 | every value (TC-TG-02, 03, 04) | every value; 24 rejected |
| `AxiMaxBeats_g` | 1 to 256, `AxiMaxBeats_g` * `AxiDataWidth_g`/8 at most 4096 bytes and the largest memory command | 1, 2, 3, 4, 7, 8, 16 (TC-TG-17, 18) | 1, 16, 256; 32 at 1024 bits; 8 at 12 address bits and 1024 bits; one beat more rejected |
| `BufferBytes_g` | 1 to 65535, at least `ChunkBytes_g` | 256, 512, 4096 | 1, 256, 65535 |
| `ChunkBytes_g` | 1 to 65535, a multiple of `AxiDataWidth_g`/8 | 32, 64, 128, 2048 | 1 and 65535 (8-bit data), 32, 64, 128, 2048; 128 above a buffer of 64 and 32 at 512 bits rejected |
| `Windows_g` | 0 to 8 | every value (TC-TG-21) | every value |
| `ExtAuth_g` | boolean | both (TC-TG-12, 16) | both |
| `TgtAddrBytes_g` | 0 to 16 | 0, 1, 8, 16 (TC-IN-10) | every value |
| `Transactions_g` | 0 to 64 | 0, 1, 4, 8, 64 (TC-IN-06, 10, TC-CO-09) | every value |
| `TickCycles_g`, `Timeout_g` | 0 to 65535 | 9, 99, 199 and 0, 200, 1000 | 0, 65535 and the defaults |
| `La0_g`, `La1_g`, `DefLaEn_g`, `Key_g`, `WinInit_g` | reset values of registers | several values (TC-MB, TC-CO) | the defaults |

## 3. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| Code coverage: the event of a discarded packet tested `Passthrough_g`, which cannot change the result | Term removed; the event follows from the first three characters only |
| With eight outstanding commands per Initiator and both cores accessing each other, both multiplexers stalled on the end of packet marker of a command: each Target waited to send a reply behind a command of its own Initiator (section 4 of the architecture) | Integration constraint in the specification and the user guide: one outstanding command with reply per Initiator between mutual Initiators, or receive buffering. The core tests with mutual Initiators run with `Transactions_g` = 1; TC-CO-09 covers eight outstanding commands of one Initiator |
| A system with the core logged numeric_std metavalue warnings after the reset: the memory access block of the Target passed undefined address and size registers to `olo_axi_master_full`, which evaluates its command inputs in its idle state; the unused byte lanes of a partly filled last write word entered the ECC buffer of the master undefined; the register file converted the register address of `olo_axi_lite_slave`, undefined until the first access, in every cycle; the authorisation evaluated the undefined header copy of the command controller when the configuration changed before the first command | The registers are reset and the register address is converted only during an access (architecture D13). TC-CO-10 runs the cores with the IEEE warnings enabled and fails on a metavalue warning; it fails without each of the four changes |
| `olo_axi_master_simple` of Open Logic compared two registers it does not reset (WrTfBeats, RdTfBeats) in the idle states of its address channels: metavalue warnings from the first command of one direction until the first command of the other | The hardware was not affected. Corrected in Open Logic (fork tag 4.7.0-ft.4); TC-CO-10 accepts no metavalue warning |
| Configurations inside the declared ranges that the core could not build or execute: `AxiAddrWidth_g` 12 to 26 at 32-bit data and `AxiDataWidth_g` 8 failed elaboration in `olo_axi_master_full`; a data width that is not a power of 2 was rejected only by Open Logic; a `ChunkBytes_g` larger than `BufferBytes_g` never completes a chunk, one that is not a whole number of memory words hung single-address writes | Open Logic 4.7.0-ft.6; long accesses are split (TG-EX-08); elaboration check CO-NO-03; every value of the table above is simulated or synthesised |
| Combinations of the generics that the table above did not combine: narrow address widths with wide data. `olo_axi_master_simple` failed elaboration when the burst was longer than the largest command of the memory master (12 address bits with 1024-bit data and the default 16 beats) and, at any address width, with 1024-bit data from 128 beats and 512-bit data at 256 beats | Elaboration check CO-NO-03 for `AxiMaxBeats_g` * `AxiDataWidth_g`/8 at most 4096 bytes and the largest command; `lint/synth_check.py` builds both bounds and rejects one beat more |
| The global simulator option that disables the IEEE warnings overrode the options of the test configurations | `run.py` sets the global options before the module configurations; the positive control of TC-CO-10 fails the test when the IEEE warnings are disabled |
