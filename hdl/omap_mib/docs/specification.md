# omap_mib: Specification

## 1. Overview

`omap_mib` is the management block of OpenRMAP (blocks MG-1 and MG-2 of the architecture): the register file with the
configuration of the Target and the Initiator, the product characteristics, the error information and the event
flags with interrupt behind an AXI4-Lite slave (MG-1), and the EDAC monitor of the FT buffers of the Target with error
injection (MG-2). The register map is generated from `regs/omap_regs.yml` by `tools/regmap.py`
([register_map.md](register_map.md)).

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| MG-IF-01 | The MIB shall provide an AXI4-Lite slave (10-bit byte address, 32-bit data); registers are written as 32-bit words, unused addresses and bits read as zero. | none |
| MG-IF-02 | The MIB shall drive the configuration inputs of the Target (logical addresses, key, address windows) and of the Initiator (tick period, reply timeout) and take the indications and events of the Target, the events and the number of outstanding commands of the Initiator and the events of the packet routing. | 5.3.3.5, 5.4.3.5, 5.5.3.5 |
| MG-IF-03 | The MIB shall provide an interrupt output. | none |

### 2.2 Register file (MG-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| MG-RF-01 | The register file shall provide the logical addresses accepted by the Target (two configurable addresses with an enable each and an enable of the default address 0xFE), the key with a check enable and `Windows_g` address windows with 40-bit first and last address, enable and permissions (read, write, verified writes only, read-modify-write, single address). | 5.1.2 note 2, 5.3.3.5, 5.4.3.5, 5.5.3.5 |
| MG-RF-02 | The register file shall provide the tick period and the reply timeout of the Initiator. | 4.3.1 |
| MG-RF-03 | The register file shall show the product characteristics fixed by generics: Target and Initiator present, user port, external authorisation, number of windows, entries of the transaction table, memory word size, maximum Target SpaceWire Address, verify buffer and chunk size. | 5.8.2.3b, 5.8.2.4b, 5.8.2.5b |
| MG-RF-04 | The register file shall record the error information: the status, instruction, Initiator Logical Address, Transaction Identifier, address and reply flag of the last command of the Target with an intact header; counters of the commands executed per kind, of the replies sent, of every status code other than 0, of the packets discarded for a Header CRC error or an incomplete header, of the replies received by the Target, of the commands received without Target, of the Initiator events and of the packets of other protocols. | 5.6, 5.7.1.2c, 5.7.1.3c, error information gathering of 5.3.3, 5.4.3, 5.5.3 |
| MG-RF-05 | Sticky flags shall be set by events and cleared by writing one; counters shall be 16 bits wide, saturate and be cleared by any write to their register; an event in the cycle of a clear shall be kept. | none |
| MG-RF-06 | The interrupt output shall be the OR of the event flags enabled by the interrupt enable register. | none |
| MG-RF-07 | The reset values of the logical addresses, the key, the windows, the tick period and the timeout shall be generics, so that a core without software accepts commands. | 5.8.2.3b (accepted logical addresses at power-on) |

### 2.3 EDAC (MG-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| MG-ED-01 | The SEC and DED events of the three FT buffers of the Target (write buffer, write data and read data of the AXI master) shall be counted per channel with a DED sticky flag per channel, a read and clear per channel and a global clear; they shall also set the ECC event flags. | none (P5) |
| MG-ED-02 | A command shall inject a single or a double error into the next word written to the selected buffer. | none (P5) |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `Target_g`, `Initiator_g`, `Passthrough_g`, `ExtAuth_g` | true, true, true, false | | Shown in GENERICS |
| `Windows_g` | 4 | 0 to 8 | Implemented windows; the registers of the others read as zero and ignore writes |
| `Transactions_g`, `AxiDataWidth_g`, `TgtAddrBytes_g` | 8, 32, 8 | | Shown in GENERICS |
| `BufferBytes_g`, `ChunkBytes_g` | 256, 32 | 1 to 65535 | Shown in BUFFERS |
| `La0_g`, `La1_g`, `DefLaEn_g` | 0xFE, 0xFE, '1' | | Reset values of TGT_LA; LA0 is enabled and LA1 disabled after reset |
| `Key_g` | 0x00 | | Reset value of the key; the key is checked after reset |
| `TickCycles_g`, `Timeout_g` | 99, 0 | 0 to 65535 | Reset values of INI_TIMEOUT |
| `WinInit_g` | window 0 open | | Reset values of the windows |

## 4. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 5.7.1.2c, 5.7.1.3c | The errors "Command Received by Initiator" and "Reply Received by Target" are recorded as counters and set an event flag. |
| 5.8.2.3b, 5.8.2.4b, 5.8.2.5b | The product characteristics tables are in the user guide; the values fixed by generics can be read back from the core, the accepted logical addresses, keys and address ranges are registers. |
