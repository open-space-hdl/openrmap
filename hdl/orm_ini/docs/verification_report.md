# orm_ini: Verification Report

## 1. Test results

Run on 2026-10-07 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*orm_ini*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `orm_ini_tb` | 7 (TC-IN-06 in the configuration `no_table`) | 7 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| The decoder kept the Data CRC register after a read reply, so the Header CRC of the next reply failed | The CRC register is cleared at the end of every reply |
