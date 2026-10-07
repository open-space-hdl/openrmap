# omap_pkg: Verification Plan

## 1. Overview

The CRC function is checked against the look-up table and the test patterns of ECSS Annex A, the command codes
against ECSS Table 5-1, and the RMAP model of the testbenches against the same test patterns and against ECSS
Table 5-3. The AXI memory model is verified by the Target tests, which compare every written byte through its
backdoor.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `omap_pkg_tb` | none | Functions of `omap_pkg` and `omap_tb_rmap_pkg` |

Simulator: GHDL.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_crc_table` (TC-PKG-01) | `crcUpdate` from zero equals the table of ECSS Annex A.3 for all 256 bytes; header and data followed by their CRC give zero; the CRC of no bytes is zero | PKG-01 |
| `test_crc_patterns` (TC-PKG-02) | The twelve CRCs of the four commands and four replies of ECSS Annex A.4 | PKG-01 |
| `test_cmd_codes` (TC-PKG-03) | Kind of all 16 command codes (ECSS Table 5-1), command field and Reply Address size of instructions | PKG-02, PKG-03 |
| `test_model` (TC-PKG-04) | The model builds the four commands and replies of ECSS Annex A.4 byte for byte, with and without SpaceWire addresses; Reply SpaceWire Addresses of ECSS Table 5-3 | PKG-04 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| PKG-01 | TC-PKG-01, TC-PKG-02 |
| PKG-02, PKG-03 | TC-PKG-03 |
| PKG-04 | TC-PKG-04 |
