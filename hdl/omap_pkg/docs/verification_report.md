# omap_pkg: Verification Report

## 1. Test results

Run on 2026-10-07 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*omap_pkg*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `omap_pkg_tb` | 4 | 4 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

The CRC function and the RMAP model reproduce all twelve CRCs and all eight packets of ECSS Annex A.4. The two CRC
implementations (bitwise function of the RTL, table of the model) agree for all 256 byte values.
