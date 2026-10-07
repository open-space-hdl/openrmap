# OpenRMAP User Guide

This guide describes how to integrate the OpenRMAP core `omap_core` into an FPGA design: sources, generics, clock and
reset, interfaces, the programming sequence, the integration constraints and the conformance statement with the
product characteristics of ECSS-E-ST-50-52C clause 5.8. The architecture is described in
[architecture.md](architecture.md), the registers in the generated
[register map](../hdl/omap_mib/docs/register_map.md).

## 1. Sources

| Library | Sources | Order |
| --- | --- | --- |
| `olo` | Open Logic areas `base`, `axi` and `ft` of the submodule `open-logic/` | `open-logic/compile_order.txt` |
| `openrmap` | `hdl/<module>/src/*.vhd` of every module of `component_list.txt` | Modules in the order of `component_list.txt`; within a module packages first (`omap_pkg.vhd`, `omap_regs_pkg.vhd`) |

All sources are VHDL-2008 and contain no vendor primitive. `tools/synth_vivado.py` shows a complete source list and
the clock constraint for AMD Vivado.

## 2. Generics

| Generic | Default | Description |
| --- | --- | --- |
| `Target_g`, `Initiator_g` | true | Node type: Target and Initiator, Target only or Initiator only (ECSS 5.7.1). At least one must be true |
| `Passthrough_g` | true | User port for packets of other protocols; without it they are discarded and counted |
| `AxiAddrWidth_g` | 32 | Address width of the memory interface (12 to 40). RMAP address bits above it must be zero |
| `AxiDataWidth_g` | 32 | Data width of the memory interface (8 to 1024, power of 2); the memory word of single-address accesses |
| `AxiMaxBeats_g` | 16 | Maximum burst length of the memory interface |
| `BufferBytes_g` | 256 | Write buffer: maximum Data Length of a verified write |
| `ChunkBytes_g` | 32 | Chunk of a non-verified write that is written to memory once it is complete in the buffer |
| `Windows_g` | 4 | Address windows of the Target (0 to 8) |
| `ExtAuth_g` | false | External authorisation port |
| `TgtAddrBytes_g` | 8 | Maximum length of the Target SpaceWire Address of a request (0 to 16) |
| `Transactions_g` | 8 | Entries of the transaction table of the Initiator (0 to 64); 0 without table and timeout |
| `La0_g`, `La1_g` | 0xFE | Reset values of the two logical addresses of the Target; LA0 is enabled, LA1 disabled after reset |
| `DefLaEn_g` | '1' | Reset value of the enable of the default logical address 0xFE |
| `Key_g` | 0x00 | Reset value of the key of the Target (checked after reset) |
| `TickCycles_g`, `Timeout_g` | 99, 0 | Reset values of the tick period minus one (in cycles) and of the reply timeout (in ticks, 0 disables it) |
| `WinInit_g` | window 0 open | Reset values of the windows (`WinCfgArray_t` of `omap_pkg`) |

With the defaults a core accepts every command to 0xFE with key 0x00 on the whole address space after reset, so a
node works without software. A flight configuration narrows the windows with `WinInit_g` or by software.

## 3. Clock and reset

All of the core runs in `Clk`; there is no clock domain crossing. `Rst` is synchronous and high-active (Open Logic
convention); synchronise its release to `Clk`, for example with `olo_base_reset_gen`. The packet ports pass one
character per cycle: at 100 MHz the core keeps up with any SpaceWire link rate.

## 4. Interfaces

### 4.1 Packet ports

`S_Pkt_*` and `M_Pkt_*` are AXI4-Stream ports with one N-Char per beat, the format of the packet ports of the OpenWire
core: a beat with `TLast` = '0' carries a data character, a beat with `TLast` = '1' is the end of packet marker
(`TData(0)` = '0' EOP, '1' EEP). Connect them to the receive and transmit packet ports of a SpaceWire port; the port's
user clock is `Clk`. The first character of a received packet is its logical address (path address bytes are removed
by the network).

### 4.2 User port

With `Passthrough_g` packets whose second character is not the Protocol Identifier 0x01, or which end before it, leave
on `M_User_*` unchanged; packets offered on `S_User_*` are sent unchanged between the RMAP packets. Unconnected ready
inputs accept every packet.

### 4.3 Target memory

`M_Axi_*` is an AXI4 master with byte addresses: the RMAP Extended Address and Address form a 40-bit byte address of
which the lower `AxiAddrWidth_g` bits are used. The first data byte of a command is written to the lowest address
(little-endian byte lanes), the first byte read is returned first. Incrementing accesses may start at any byte and
have any length; a single-address access (increment bit clear) accesses one memory word repeatedly and must be
aligned to the word with a length that is a multiple of it. A read-modify-write reads and writes the same bytes in
two AXI transactions; it is atomic for RMAP, not for other masters of the memory. An error response ends a write or
read-modify-write with status 1 and a read reply with an EEP.

### 4.4 External authorisation and indications

With `ExtAuth_g` every command that passes the internal checks is presented on `Auth_*` (`Auth_Valid` held until
`Auth_RspValid`); `Auth_RspAccept` = '0' rejects it with status 10 (ECSS 5.3.3.5, 5.4.3.5, 5.5.3.5). `Ind_*` gives a
one-cycle indication of every command with an intact header at its end, with its fields, its status and whether a
reply was sent (ECSS 5.3.3.7, 5.4.3.7, 5.5.3.8).

### 4.5 Initiator

A request on `S_Req_*` (valid / ready) carries the command field (bits 5 to 2 of the instruction), the Target
SpaceWire Address (byte i in bits 8i + 7 to 8i, `S_Req_TgtAddrLen` bytes, byte 0 sent first), the Target Logical
Address, the key, the Reply Address (byte i in bits 8i + 7 to 8i, `S_Req_ReplyAddrLen` bytes; the core pads it to
whole words with leading 0x00), the Initiator Logical Address, the Transaction Identifier, the 40-bit address and the
Data Length. Write and read-modify-write requests take Data Length bytes on `S_ReqData_*` (for read-modify-write the
data followed by the mask).

Every reply with an intact header gives a confirmation on `M_Conf_*` with Transaction Identifier, instruction, status,
Data Length and local error (`M_Conf_Error`: 0 none, 1 data error, 2 timeout, 3 Transaction Identifier in use). Read
data leaves on `M_RepData_*` while the reply arrives, the last byte with `TLast`; it is valid only when the
confirmation reports no data error (ECSS 5.4.3.12).

With `Transactions_g` > 0 a request with reply is registered in the transaction table; replies that match no
registered command are discarded, a request with a Transaction Identifier in use is confirmed with error 3 and not
sent, and a full table holds the next request. A registered command without reply after `Timeout` ticks is confirmed
with error 2.

### 4.6 Register file and interrupt

`S_AxiLite_*` is an AXI4-Lite slave with a 10-bit byte address and 32-bit registers; `Irq` is the OR of the enabled
event flags. The register map is in [register_map.md](../hdl/omap_mib/docs/register_map.md), the C header in
`sw/omap_regs.h`.

## 5. Programming sequence

1. Read ID (0x4F4D4101) and GENERICS to identify the core and its configuration.
2. Target: write the logical addresses and their enables (TGT_LA), the key (TGT_KEY) and the address windows
   (WIN_BASE, WIN_LAST, then WIN_CTRL with the permissions and ENABLE).
3. Initiator: write the tick period and the reply timeout (INI_TIMEOUT).
4. Write IRQ_EN for the events of interest; clear EVENTS by writing ones.
5. In operation read the counters (cleared by a write), TGT_LAST for the last command of the Target and ECC_STATUS
   and ECC_COUNT for the EDAC of the buffers.

## 6. Integration constraints

| Constraint | Reason |
| --- | --- |
| Two nodes that are Initiator and Target of each other on one link need `Transactions_g` = 1 (one outstanding command with reply per Initiator), or receive buffering in front of each core for the commands the other node can have outstanding | A Target receives the next command only after its reply has been sent, and a reply waits behind a command of the own Initiator. With several outstanding commands in both directions both Targets can wait while each link carries a command the other Target does not take ([omap_core architecture](../hdl/omap_core/docs/architecture.md), section 4) |
| `M_RepData_*`, `M_Conf_*` and `M_User_*` must be served | A stalled output stalls the received packet stream and the link |
| RMAP address bits above `AxiAddrWidth_g` must be zero in the windows | Such commands are rejected with status 10 |

## 7. Conformance

OpenRMAP with `Target_g` and `Initiator_g` true implements the subset "RMAP Initiator and Target" of ECSS 5.8.1 with
the write, read and read-modify-write commands:

"This product conforms to the SpaceWire RMAP Write, Read and Read-Modify-Write specifications of the ECSS SpaceWire
Protocols Standard (ECSS-E-ST-50-52)."

With `Initiator_g` false: "This product conforms to the SpaceWire RMAP Target only specification of the ECSS
SpaceWire Protocols Standard (ECSS-E-ST-50-52)." With `Target_g` false: "This product conforms to the SpaceWire RMAP
Initiator only specification of the ECSS SpaceWire Protocols Standard (ECSS-E-ST-50-52)."

The [compliance matrix](compliance.md) lists the requirements and test cases of every clause. The product
characteristics of the Target (ECSS 5.8.2.3b, 5.8.2.4b, 5.8.2.5b) follow; values in brackets are generics or
registers.

### 7.1 Write command (ECSS Table 5-6)

| Action | Supported | Maximum Data Length (bytes) | Non-aligned access accepted |
| --- | --- | --- | --- |
| 8-bit write | Yes | 16 777 215 | Yes |
| 16-bit write | Yes | 16 777 215 | Yes |
| 32-bit write | Yes | 16 777 215 | Yes |
| 64-bit write | Yes | 16 777 215 | Yes |
| Verified write | Yes | `BufferBytes_g` (BUFFERS.VERIFY_BYTES) | Yes |
| Single-address write | Yes | 16 777 215, multiple of the memory word | No: aligned to the memory word (`AxiDataWidth_g` / 8 bytes, GENERICS.WORD_BYTES) |

| Characteristic | Value |
| --- | --- |
| Word or byte address | Byte address |
| Endian order | First byte received goes to the lowest address (little-endian byte lanes of the AXI4 memory interface) |
| Accepted logical addresses | 0xFE (`DefLaEn_g`) and `La0_g` at power-on; TGT_LA after initialisation |
| Target logical address in reply | What was in the command |
| Accepted keys | `Key_g` at power-on; TGT_KEY after initialisation, every key with KEY_EN = 0 |
| Accepted address ranges | The enabled windows with write permission (`WinInit_g` at power-on, WIN registers after initialisation), within `AxiAddrWidth_g` |
| Address incrementation | Incrementing and single address |
| Status codes returned | 1 to 7, 9, 10, 12 |

### 7.2 Read command (ECSS Table 5-8)

| Action | Supported | Maximum Data Length (bytes) | Non-aligned access accepted |
| --- | --- | --- | --- |
| 8-bit read | Yes | 16 777 215 | Yes |
| 16-bit read | Yes | 16 777 215 | Yes |
| 32-bit read | Yes | 16 777 215 | Yes |
| 64-bit read | Yes | 16 777 215 | Yes |
| Single-address read | Yes | 16 777 215, multiple of the memory word | No: aligned to the memory word |

| Characteristic | Value |
| --- | --- |
| Word or byte address | Byte address |
| Endian order | The byte at the lowest address is returned first (little-endian byte lanes) |
| Accepted logical addresses | As for the write command |
| Target logical address in reply | What was in the command |
| Accepted keys | As for the write command |
| Accepted address ranges | The enabled windows with read permission, within `AxiAddrWidth_g` |
| Address incrementation | Incrementing and single address |
| Status codes returned | 2, 3, 6, 7, 10, 12; a memory error during the data ends the reply with an EEP |

### 7.3 Read-modify-write command (ECSS Table 5-10)

| Action | Supported | Maximum Data Length (bytes) | Non-aligned access accepted |
| --- | --- | --- | --- |
| 8-bit read-modify-write | Yes | 2 (data and mask) | Yes |
| 16-bit read-modify-write | Yes | 4 | Yes |
| 24-bit read-modify-write | Yes | 6 | Yes |
| 32-bit read-modify-write | Yes | 8 | Yes |
| 64-bit read-modify-write | No | - | - |

| Characteristic | Value |
| --- | --- |
| Word or byte address | Byte address |
| Endian order | First byte of the data and of the mask apply to the lowest address |
| Accepted logical addresses | As for the write command |
| Target logical address in reply | What was in the command |
| Accepted keys | As for the write command |
| Accepted address ranges | The enabled windows with read-modify-write permission, within `AxiAddrWidth_g` |
| Status codes returned | 1 to 7, 10 to 12 |

## 8. Verification and tools

```shell
python run.py -p 8                          # regression with GHDL
python run.py --questa --coverage <test>    # code coverage with QuestaSim
python lint/lint.py                         # VSG
python lint/synth_check.py                  # synthesizability of three node types with GHDL
python tools/compliance.py --check          # ECSS traceability
python tools/regmap.py --check              # generated register map up to date
python tools/synth_vivado.py --part <part>  # resources and timing with AMD Vivado (licence for the part needed)
```
