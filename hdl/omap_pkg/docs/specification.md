# omap_pkg: Specification

## 1. Overview

`omap_pkg` contains the definitions shared by all OpenRMAP modules: the RMAP field values, the instruction bits, the
command codes, the status codes, the RMAP CRC, the decoded command header and the address windows of the Target.
The shared verification components in `tb/` (RMAP model, AXI memory model, VVC wrappers) are verified with this
module.

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| PKG-01 | The package shall compute the RMAP CRC of ECSS 5.2: generator polynomial x^8 + x^2 + x + 1, register initialised to zero, bytes in transmission order with the least significant bit first, the CRC byte formed in reversed bit order; the CRC over the covered bytes followed by their CRC byte shall be zero. | 5.2 |
| PKG-02 | The package shall classify the command codes of ECSS Table 5-1 into write, read, read-modify-write and invalid, and give the command field and the size of the Reply Address field of an instruction. | 5.1.4, 5.1.6b |
| PKG-03 | The package shall define the Protocol Identifier 0x01, the default logical address 0xFE and the status codes of ECSS Table 5-4. | 5.1.3, 5.1.2, 5.6 |
| PKG-04 | The RMAP model of the testbenches shall build commands and replies byte by byte as ECSS 5.1, 5.3.1, 5.3.2, 5.4.1, 5.4.2, 5.5.1 and 5.5.2 define them, with its own CRC implementation (table method of ECSS Annex A.3), and form the Reply SpaceWire Address from the Reply Address field as ECSS 5.1.6c to e define it. | none (verification) |

## 3. Configuration parameters

None. The package has constants and pure functions only.
