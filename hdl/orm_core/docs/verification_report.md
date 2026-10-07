# orm_core: Verification Report

## 1. Test results

Run on 2026-10-07 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*orm_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `orm_core_tb` | 9 (TC-CO-05 in `limited`, TC-CO-06 in `no_pass`, TC-CO-09 in `transactions8`) | 9 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| Code coverage: the event of a discarded packet tested `Passthrough_g`, which cannot change the result | Term removed; the event follows from the first three characters only |
| With eight outstanding commands per initiator and both cores accessing each other, both multiplexers stalled on the end of packet marker of a command: each target waited to send a reply behind a command of its own initiator (section 4 of the architecture) | Integration constraint in the specification and the user guide: one outstanding command with reply per initiator between mutual initiators, or receive buffering. The core tests with mutual initiators run with `Transactions_g` = 1; TC-CO-09 covers eight outstanding commands of one initiator |
