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
| `openrmap` | `hdl/<module>/src/*.vhd` of every module of `component_list.txt` | `compile_order.txt`: the modules in the order of `component_list.txt`, within a module packages first |

All sources are VHDL-2008 and contain no vendor primitive. `tools/synth_vivado.py` shows a complete source list and
the clock constraint for AMD Vivado.

## 2. Generics

| Generic | Default | Description |
| --- | --- | --- |
| `Target_g`, `Initiator_g` | true | Node type: Target and Initiator, Target only or Initiator only (ECSS 5.7.1). At least one must be true |
| `Passthrough_g` | true | User port for packets of other protocols; without it they are discarded and counted |
| `AxiAddrWidth_g` | 32 | Address width of the memory interface (12 to 40). RMAP address bits above it must be zero. An access longer than one command of the memory master, 2^(`AxiAddrWidth_g` - 2) - `AxiDataWidth_g`/8 bytes (2^(`AxiAddrWidth_g` - 1) - 1 at 8-bit data, at most 2^24 - `AxiDataWidth_g`/8), is split into several commands |
| `AxiDataWidth_g` | 32 | Data width of the memory interface (8 to 1024, power of 2, checked at elaboration); the memory word of single-address accesses |
| `AxiMaxBeats_g` | 16 | Maximum burst length of the memory interface (1 to 256); longer accesses are split into several bursts. `AxiMaxBeats_g` * `AxiDataWidth_g`/8 is at most 4096 bytes and at most 2^(`AxiAddrWidth_g` - 2) bytes (2^(`AxiAddrWidth_g` - 1) at 8-bit data), checked at elaboration: no burst is longer |
| `BufferBytes_g` | 256 | Write buffer: maximum Data Length of a verified write; at least `ChunkBytes_g` |
| `ChunkBytes_g` | 32 | Chunk of a non-verified write that is written to memory once it is complete in the buffer; a whole number of memory words (a single-address write moves whole words) and at most `BufferBytes_g`, both checked at elaboration. The chunk is at most one command of the memory master (`AxiAddrWidth_g`) |
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
convention); synchronise its release to `Clk` with a triplicated synchroniser, for example `olo_base_reset_gen` with
`SyncTmr_g` = true (section 6). The packet ports pass one character per cycle: at 100 MHz the core keeps up with
any SpaceWire link rate.

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

## 6. Protection scope

The core is designed for radiation environments together with the triple modular redundancy (TMR) of the synthesis
tool, like the Open Logic ft entities it is built on. It protects the parts in the first rows itself and relies on
TMR for all other logic:

| Part | Protection | Indication and test |
| --- | --- | --- |
| Data buffers of the RMAP Target: write buffer (`olo_ft_fifo_sync`, EDAC channel 0), write and read data buffers of the memory master `olo_ft_axi_master_full` (channels 1 and 2) | SECDED ECC of the Open Logic ft entities: a single error is corrected, a double error is detected and contained: a write or read-modify-write ends with the status "general error code" (1), a read reply ends with an EEP after the data (see below) | EVENTS.ECC_SEC, EVENTS.ECC_DED, ECC_STATUS, ECC_SELECT and ECC_COUNT, `Irq` through IRQ_EN; status 1 in the reply, TGT_LAST and the indication of the command; error injection through the ECC_INJECT register |
| Clock domain crossings and reset synchronisers | The core has one clock domain and no synchroniser of its own. Synchronise the release of `Rst` with a triplicated synchroniser, for example `olo_base_reset_gen` with `SyncTmr_g` = true (section 3): three synchroniser chains and a majority voter. Their registers carry the Synplify attribute `syn_radhardlevel` = `none`, so the TMR of the synthesis tool adds no voters between the stages | none |
| State machines | Recovery state through the `when others` branch and the reset; a command of the Initiator whose reply is lost ends with the reply timeout (INI_TIMEOUT, with `Transactions_g` > 0) | none |
| All other logic: registers of the control and data paths, counters, pointers, pipeline registers, the transaction table of the Initiator and the register file | TMR of the synthesis tool (for example `syn_radhardlevel` = `tmr` with Synplify, or the equivalent setting of the tool chain). The core adds no protection of its own for this logic; without TMR, an upset in it is not covered | synthesis report |

A double error is never passed on as valid data. The buffers hold one byte per ECC word, so ECC_COUNT counts corrected
and detected bytes. In a write the byte with the double error is written to memory with the other data of the
command, and the reply and the indication carry status 1, so the Initiator knows that the addressed memory holds
undefined data and can repeat the write. This applies to verified writes as well: the Data CRC is checked as the data
enters the write buffer, so a double error that arises in the buffer afterwards is reported, not prevented. A
read-modify-write with a double error ends with status 1; after a double error in the read data nothing is written.
In a read reply the data is followed by an EEP instead of the Data CRC and the EOP (ECSS 5.4.3.10c.1), so the
Initiator recognises the data as invalid. ECC_INJECT writes a single or a double error into the next byte written to a
buffer for tests of the software.

The integrator:

- enables the TMR of the synthesis tool for the core and the logic around it,
- checks in the synthesis report that TMR was applied, that the synchroniser chains of the crossings were not
  triplicated a second time, and that no register-based storage meant to be protected by TMR was inferred as a RAM
  primitive,
- requests safe state machines, so that synthesis keeps the `when others` branches (AMD Vivado: property
  `FSM_SAFE_STATE` = `default_state` on the state registers; Synplify: attribute `syn_encoding` = `safe`),
- protects the configuration memory of SRAM-based FPGAs by scrubbing; this is part of the FPGA design, not of the
  core.

The ECC paths are verified in simulation by error injection. Whether the protection as a whole meets the
requirements of a mission is shown by a radiation test with the core in operation (TRL 5).

## 7. Integration constraints

| Constraint | Reason |
| --- | --- |
| TMR of the synthesis tool enabled for the core | The core protects its data buffers itself and relies on TMR for all other logic (section 6) |
| Two nodes that are Initiator and Target of each other on one link need `Transactions_g` = 1 (one outstanding command with reply per Initiator), or receive buffering in front of each core for the commands the other node can have outstanding | A Target receives the next command only after its reply has been sent, and a reply waits behind a command of the own Initiator. With several outstanding commands in both directions both Targets can wait while each link carries a command the other Target does not take ([omap_core architecture](../hdl/omap_core/docs/architecture.md), section 4) |
| `M_RepData_*`, `M_Conf_*` and `M_User_*` must be served | A stalled output stalls the received packet stream and the link |
| RMAP address bits above `AxiAddrWidth_g` must be zero in the windows | Such commands are rejected with status 10 |

## 8. Conformance

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

### 8.1 Write command (ECSS Table 5-6)

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

A verified write is checked with the Data CRC and the Data Length before any byte is written to memory (ECSS
5.3.3.6.2, 5.3.3.6.4). The check covers the data as received: a double error that arises afterwards in the write
buffer or in the write data of the memory master is not kept out of memory, and the command ends with status 1
(section 6).

### 8.2 Read command (ECSS Table 5-8)

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

### 8.3 Read-modify-write command (ECSS Table 5-10)

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

## 9. Performance

All numbers are cycles of `Clk`, measured in simulation by the test cases in the last column. Symbols: n the Data Length
in bytes (n bytes read and modified for a read-modify-write), W = `AxiDataWidth_g`/8, B = `AxiMaxBeats_g`, C the chunk
(`ChunkBytes_g`, at most one command of the memory master, section 2), P the bytes of the Target SpaceWire Address and R
the bytes of the Reply Address (padded to whole words) of a request, L the memory latency: the cycles the memory adds to
a slave that presents the first read beat in the cycle after the AR handshake and the write response in the cycle after
the last W beat.

### 9.1 Packet ports

The packet ports and the user port carry one character per cycle. A received packet costs up to four further cycles
in the demultiplexer (three characters of lookahead and a decision cycle), a sent packet one idle cycle at its start
in the multiplexer.

| Packet | Cycles | Test |
| --- | --- | --- |
| Command at the Target: write of n + 18 characters (without Reply Address), read of 17, read-modify-write of 2n + 18 | n + 22, 21, 2n + 22 at the Target; up to five more at the packet input of the core | TC-TG-19, TC-CO-11 |
| Command of the Initiator: write of n + P + R + 18 characters, read of 17 (without addresses) | the last character n + P + R + 22 and 20 cycles after the request; the first after 4 cycles (3 with a Target SpaceWire Address) | TC-IN-09 |
| Reply at the Initiator: write reply of 9 characters, read reply of n + 14 | 10 and n + 15 at the Initiator, 14 for a write reply at the packet input of the core | TC-IN-09, TC-CO-11 |

The Target takes the end of a command only after the reply to the previous command has been sent (architecture of
`omap_core`, section 4). The Initiator takes the next request with the end of packet marker of a command: writes
without reply follow every n + 22 cycles (TC-IN-09).

### 9.2 Memory rates of the Target

The memory master packs one byte per cycle, its read buffer holds two bursts, and it issues at most one read
transaction every four cycles. It takes the next chunk of a non-verified write while the bytes of the current one pass,
so the chunks follow each other without a gap. A chunk is split into write transactions of T = min(C, WB) bytes; at
most four are open, and each holds its place for L + 5 + T/W cycles. With single-beat bursts (B = 1) the issue of the
transactions limits the write rate at a low latency: the master starts a transaction only when its word is in its data
buffer of two words, so that two transactions take at most 9 cycles, and it needs 3 more cycles to take the next
chunk. The n = C/W transactions of a chunk thus take at most 4.5n + 3 cycles, and the table gives a lower bound of the
write rate.

| Access | Bytes per cycle | With the defaults (W 4, B 16, C 32) | Test |
| --- | --- | --- | --- |
| Read | min(1, 2WB / (L + 7 + W (B - 1)), WB / 4) | 1 up to L = 61, 0.871 at L = 80 | TC-TG-18 |
| Non-verified write | min(1, 4T / (L + 5 + T/W)); with B = 1 at least C / (4.5C/W + 3) | 1 up to L = 115, 0.740 at L = 160 (C 128: 1 up to L = 235) | TC-TG-18 |

Short bursts reduce the rates: with B = 1 at 32 bit a write reaches at least 0.821 bytes per cycle at L = 0 (0.842 in
TC-TG-18), and at L = 40 a read reaches 0.170 and a write 0.348 bytes per cycle; at 16 bit with B = 1 a read reaches
0.5 bytes per cycle at L = 0. A non-verified write is taken at one character per cycle while the bytes not yet written
fit into the write buffer (`BufferBytes_g`); a longer write is taken at the write rate. A verified write writes its
data only after the Data CRC is checked, so its memory write follows its reception.

### 9.3 Command timing of the Target

| Command | Cycles | Test |
| --- | --- | --- |
| Read: end of the command to the first reply character | 5 | TC-TG-19 |
| Read reply of n + 14 characters | n + 17 + W + L at a read rate of 1 | TC-TG-19 |
| Non-verified write of n bytes, n up to C and WB, aligned: end of the command to the reply | n + ceil(n / W) + 19 + L | TC-TG-19 |
| Read-modify-write: end of the command to the reply; reply of n + 14 characters | 2n + 38 + W + 2L; n + 16 | TC-TG-19 |
| Reads back to back | n + 23 + W + L per command | TC-TG-19, TC-CO-11 |
| Non-verified writes of n = kC bytes (k >= 2) back to back | at most n (C + 9) / C + C + 29 + L per command (C 32, n 256: 381 at L = 0) | TC-TG-19, TC-CO-11 |
| Read-modify-writes of 4 bytes back to back | 76 + W + 2L per command | TC-TG-19 |

### 9.4 Initiator

The read data of a reply leaves at one byte per cycle, the last byte 3 cycles after the end of packet marker of the
reply; the confirmation follows 3 cycles (write reply) or 5 cycles (read reply) after it (TC-IN-09). Between two
cores without network delay a read of n >= 4 bytes takes n + 63 cycles from the request to the confirmation (64-bit
memory, L = 0; TC-CO-11).

## 10. Verification and tools

```shell
python run.py -p 8                          # regression with GHDL
python run.py --questa --coverage <test>    # code coverage with QuestaSim
python lint/lint.py                         # VSG
python lint/synth_check.py                  # synthesizability at the generic values, GHDL
python tools/compliance.py --check          # ECSS traceability
python tools/regmap.py --check              # generated register map up to date
python run.py --compile-order               # compile_order.txt of the synthesis sources
python tools/synth_vivado.py --part <part>  # resources and timing with AMD Vivado
```

## 11. Corrected defects

Defects of earlier versions that change the behaviour of a system. The version is the Open Logic tag that the
submodule `open-logic/` pins.

| Defect | Affected | Correction |
| --- | --- | --- |
| Memory accesses of the Target with `AxiMaxBeats_g` smaller than `AxiDataWidth_g`/8 (32-bit bus with 1 to 3 beats, 64-bit bus with 1 to 7): every burst of an access longer than one burst used the address of the first burst. Reads returned the data of the first burst again; writes overwrote the words of the first burst, with an unaligned start also the bytes before the start address in its first word, and left the following addresses unwritten; read-modify-writes across a word boundary with one beat read and wrote the first word in place of the second. The reply reported success. The cause is the address increment of `olo_axi_master_simple` of Open Logic | Every version with Open Logic up to 4.7.0-ft.4; with 16 beats (the default) or any `AxiMaxBeats_g` of at least `AxiDataWidth_g`/8 not affected | Open Logic 4.7.0-ft.5; TC-TG-17 |
| A non-verified single-address write never completed when `ChunkBytes_g` was not a whole number of memory words (with the default `ChunkBytes_g` of 32: `AxiDataWidth_g` 512 and 1024); the Target accepted no further command | Every earlier version | `ChunkBytes_g` must be a multiple of `AxiDataWidth_g`/8, checked at elaboration; TC-TG-02 at every data width |
| `omap_core` with `AxiAddrWidth_g` 12 to 26 at 32-bit data (at other data widths correspondingly) or with `AxiDataWidth_g` 8 failed elaboration in `olo_axi_master_full` of Open Logic | Every version with Open Logic up to 4.7.0-ft.5 | Open Logic 4.7.0-ft.6; accesses longer than one command of the memory master are split; TC-TG-20 |
| `omap_core` with a long burst failed elaboration in `olo_axi_master_simple` of Open Logic: at narrow address widths when the burst was longer than the largest command of the memory master (12 address bits with 1024-bit data from 16 beats, the default; with 512-bit data from 64 beats), and at any address width with 1024-bit data from 128 beats and with 512-bit data at 256 beats | Measured with Open Logic 4.7.0-ft.6 | These configurations are rejected at elaboration with a message (`AxiMaxBeats_g` row in section 2); every allowed one builds |
