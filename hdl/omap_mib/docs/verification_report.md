# omap_mib: Verification Report

## 1. Test results

Run on 2026-10-17 with GHDL 6.0.0 (mcode) and QuestaSim (without and with code coverage), VUnit 5.0.0.dev7,
UVVM 2026.03.20: `python run.py "*omap_mib*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `omap_mib_tb` | 7 | 7 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| The register map generator named the base address of a register array and a register of the array alike (`RegWinBase_c`) | The array is named WINDOW (`RegWindowBase_c`, `RegWindowStride_c`) |
| The register address of the AXI4-Lite slave, undefined until the first access, was converted in every cycle: numeric_std metavalue warnings in simulation | Converted only during an access (architecture D13); TC-CO-10 checks it at core level |
