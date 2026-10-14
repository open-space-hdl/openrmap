# omap_core: Verification Report

## 1. Test results

Run on 2026-10-14 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*omap_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `omap_core_tb` | 10 (TC-CO-05 in `limited`, TC-CO-06 in `no_pass`, TC-CO-09 in `transactions8`, TC-CO-10 in `ieee_warnings`) | 10 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| Code coverage: the event of a discarded packet tested `Passthrough_g`, which cannot change the result | Term removed; the event follows from the first three characters only |
| With eight outstanding commands per Initiator and both cores accessing each other, both multiplexers stalled on the end of packet marker of a command: each Target waited to send a reply behind a command of its own Initiator (section 4 of the architecture) | Integration constraint in the specification and the user guide: one outstanding command with reply per Initiator between mutual Initiators, or receive buffering. The core tests with mutual Initiators run with `Transactions_g` = 1; TC-CO-09 covers eight outstanding commands of one Initiator |
| A system with the core logged numeric_std metavalue warnings after the reset: the memory access block of the Target passed undefined address and size registers to `olo_axi_master_full`, which evaluates its command inputs in its idle state; the unused byte lanes of a partly filled last write word entered the ECC buffer of the master undefined; the register file converted the register address of `olo_axi_lite_slave`, undefined until the first access, in every cycle; the authorisation evaluated the undefined header copy of the command controller when the configuration changed before the first command | The registers are reset and the register address is converted only during an access (architecture D13). TC-CO-10 runs the cores with the IEEE warnings enabled and fails on a metavalue warning; it fails without each of the four changes |
| `olo_axi_master_simple` of Open Logic compares two registers it does not reset (WrTfBeats, RdTfBeats) in the idle states of its address channels: metavalue warnings from the first command of one direction until the first command of the other | The hardware is not affected. TC-CO-10 accepts only these two comparisons in the memory master of the Target; the exception is removed when the Open Logic version used by the core contains the fix |
| The global simulator option that disables the IEEE warnings overrode the options of the test configurations | `run.py` sets the global options before the module configurations; the positive control of TC-CO-10 fails the test when the IEEE warnings are disabled |
