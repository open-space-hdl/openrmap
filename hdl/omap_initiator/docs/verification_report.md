# omap_initiator: Verification Report

## 1. Test results

Run on 2026-10-07 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*omap_initiator*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `omap_initiator_tb` | 8 (TC-IN-06 in the configuration `no_table`) | 8 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| The decoder kept the Data CRC register after a read reply, so the Header CRC of the next reply failed | The CRC register is cleared at the end of every reply |
| Code coverage review: a command whose reply was related to it stayed in the table until the confirmation handshake, so its timer could expire while the reply was received or its confirmation was held; the command was then confirmed twice, with the reply and with a timeout | The entry is removed in the cycle of the lookup (`omap_initiator_rx`, `omap_initiator_tt`); TC-IN-05 holds the confirmations and checks that no timeout follows |
| Code coverage: no test for a held confirmation, for late data of a rejected request, for a rejected read request, for a read reply ending after the Header CRC and for a reset in the middle of a request | Tests added to TC-IN-03, TC-IN-04 and TC-IN-05; TC-IN-08 added |
| Code coverage: the selection of the confirmation source tested the ready signal in a branch that is only reached when it is set | Term removed |
