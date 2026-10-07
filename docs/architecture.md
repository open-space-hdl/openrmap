# OpenRMAP Architecture

Version 0.1. This file is the reference for the architecture and is versioned with the code.

## 1 Purpose, scope and references

This document defines the architecture of OpenRMAP, an implementation of the SpaceWire Remote Memory Access
Protocol (RMAP) with an RMAP Target and an RMAP Initiator. Together with ECSS-E-ST-50-52C it is the complete basis
for the implementation: it fixes the building blocks, their interfaces, the ECSS requirements each block owns and the
Open Logic entities each block is built from.

### In scope

- RMAP Target: decoding and checking of write, read and read-modify-write commands, authorisation by logical
  address, key and address windows, access to the Target memory through an AXI4 master, replies with all status
  codes of the standard, verified and non-verified writes, incrementing and single-address accesses.
- RMAP Initiator: encoding of write, read and read-modify-write commands from a request interface, decoding and
  checking of replies, confirmations to the user, association of replies with commands by the Transaction
  Identifier, optional reply timeout.
- Routing of the packets of a SpaceWire port: RMAP commands to the Target, RMAP replies to the Initiator, packets
  of other protocols to a user port; merging of the outgoing packets.
- Error information gathering, configuration and status in a register file behind an AXI4-Lite port, fault
  tolerance and the verification architecture.

### Out of scope

- The SpaceWire port itself (Encoding, Data Link and Network layers of ECSS-E-ST-50-12C). OpenRMAP connects to the
  packet ports of a SpaceWire port; its packet interfaces use the N-Char format of the OpenWire core.
- RMAP configuration ports of routing switches with implicit return addresses (ECSS 5.1.6i): OpenRMAP is an RMAP
  node and replies to the Reply Address of the command.
- Protocols other than RMAP (ECSS-E-ST-50-51 protocol identifiers other than 1): their packets pass through the user
  port unchanged.

### Target technology

OpenRMAP contains no vendor code. All buffers are Open Logic fault-tolerant entities, the memory interface is an
AXI4 master and all other interfaces are AXI4-Stream and AXI4-Lite. The core runs on any FPGA.

### Project

OpenRMAP is an open Remote Memory Access Protocol implementation that is based on the Open Logic VHDL Library. The
code lives in [open-space-hdl/openrmap](https://github.com/open-space-hdl/openrmap) under the PSI HDL Library License,
Version 1.0, the licence of Open Logic. Open Logic is pinned to `feature/fault-tolerant-all-entities` of
rustyqt/open-logic (6850713).

### References

| ID | Document | Version used |
| --- | --- | --- |
| \[ECSS\] | ECSS-E-ST-50-52C, SpaceWire: Remote memory access protocol | 5 February 2010 |
| \[SPW\] | ECSS-E-ST-50-12C Rev.1, SpaceWire: Links, nodes, routers and networks | 15 May 2019 |
| \[PID\] | ECSS-E-ST-50-51C, SpaceWire protocol identification | 5 February 2010 |
| \[OLO\] | [Open Logic, branch feature/fault-tolerant-all-entities](https://github.com/rustyqt/open-logic/tree/feature/fault-tolerant-all-entities) | 6850713 |

### Conventions

- Requirement references are ECSS-E-ST-50-52C clause numbers with the requirement letter, for example ECSS
  5.3.3.6.3a. A range such as 5.3.3.4.2 to 5.3.3.4.8 means all requirements of those clauses.
- Coding conventions: those of Open Logic (naming, two-process style, synchronous high-active resets, VSG rules), entity
  prefix `omap_`, VHDL library `openrmap`; see [conventions.md](conventions.md).
- "FT" (fault-tolerant) means the Open Logic `olo_ft_*` entities: SECDED ECC on every buffer.

| Term | Meaning |
| --- | --- |
| Command | RMAP packet with packet type 0b01 (ECSS 5.1.4.2) |
| Reply | RMAP packet with packet type 0b00 |
| TLA, ILA | Target and Initiator Logical Address (ECSS 5.1.2, 5.1.7) |
| TID | Transaction Identifier (ECSS 5.1.8) |
| RAL | Reply Address Length field (ECSS 5.1.4.4) |
| RMW | Read-modify-write |
| Word | AXI data word of the Target memory interface (`AxiDataWidth_g` bits) |
| N-Char stream | Packet stream of the OpenWire core: one data character per beat, the end of packet marker as a separate beat with `TLast` = '1' (`TData(0)` = '0' EOP, '1' EEP) |

## 2 RMAP functional overview

RMAP writes and reads memory in a remote SpaceWire node (ECSS 4.1). An Initiator sends a command, the Target checks
it, asks its user application for authorisation, accesses its memory and returns a reply when one is requested.
All operations are posted: many commands can be outstanding, and replies are associated with commands by the
Transaction Identifier (ECSS 4.3.1).

| Function | ECSS clauses |
| --- | --- |
| Command and reply fields | 5.1 |
| Cyclic redundancy code of header and data | 5.2 |
| Write command, write reply, write action (verified and non-verified, acknowledged and not acknowledged) | 5.3 |
| Read command, read reply, read action | 5.4 |
| Read-modify-write command, reply and action | 5.5 |
| Error and status codes | 5.6 |
| Initiator-only and Target-only nodes, partial implementations | 5.7 |
| Conformance statements and product characteristics | 5.8 |

Three properties of the standard shape the architecture more than any single feature:

- **The Header CRC decides whether a reply is possible.** A command with a header error is discarded without reply
  because the Reply Address cannot be trusted (ECSS 5.3.3.4.5). Every other error is reported to the Reply Address.
  The Target therefore checks the complete header before it acts on any field of it.
- **A non-verified write writes data before its Data CRC is known.** The Target must write while the packet arrives
  (ECSS 5.3.3.6.9) and must stop writing at an early end of the packet (ECSS 5.3.3.6.11). Data is committed to
  memory in chunks that are complete in the buffer, so the bytes before an early end of packet, which include the
  Data CRC, are never written as data.
- **A verified write and a read-modify-write act only on a complete, checked packet.** Their data is buffered and
  checked before memory is touched (ECSS 5.3.3.6.2, 5.5.3.4.8); the buffer size limits the length (ECSS 5.3.3.6.3).

## 3 Design drivers

| Driver | Consequence |
| --- | --- |
| Use in space: single event upsets in buffers and registers | SECDED ECC on every buffer, state machines with a recovery state, an EDAC monitor in the register file (P5) |
| Protection of the Target memory | Authorisation by logical address, key, address windows with permissions and an optional application port (P6) |
| Integration with a SpaceWire port | Packet ports in the N-Char format of the OpenWire core, packets of other protocols passed through (P7) |
| Technology independence | AXI4, AXI4-Stream and AXI4-Lite interfaces, no vendor primitive (P10) |
| Verifiability | Every block verified through its ports against an independent RMAP model and the CRC test patterns of ECSS Annex A (P8, section 9) |
| Reuse | Every generic function comes from Open Logic; custom logic is limited to RMAP (P9) |

## 4 Design goals

| Goal | Implementation |
| --- | --- |
| Defined handshakes between blocks | Every internal data path is a valid / ready stream or a stream of one-cycle events (P2) |
| One protocol function per block | A block implements one ECSS function; no clause is owned by two blocks (P1) |
| Deterministic error reporting | One fixed priority of the status codes (D9) and one reply per checked command |
| Fault tolerance | FT buffers, safe state machines, contained double errors (P5) |
| One management interface | All parameters in a register file behind one AXI4-Lite port (P4) |
| Tests independent of the design hierarchy | Tests observe only ports and the register file (section 9) |

## 5 Design principles

| ID | Principle | Rule for the implementation |
| --- | --- | --- |
| P1 | One protocol function per block | A block implements one ECSS function. Its specification names the clauses it owns; no clause is owned by two blocks. |
| P2 | Streams everywhere | Every data path between blocks is a valid / ready stream (Open Logic AXI4-Stream conventions) or a valid-only stream of events. |
| P3 | One clock domain | All blocks run in `Clk`. The clock domain crossings of the SpaceWire port stay in the port. |
| P4 | One management interface | All configuration, status and error information lives in one register file behind one AXI4-Lite port, generated from a single register description (VHDL package, documentation, C header). |
| P5 | Fault tolerance by construction | All buffers are `olo_ft_*` entities (SECDED ECC). State machines have a defined recovery state. ECC events are counted in the register file; a double error is contained and never written to memory or sent as valid data. |
| P6 | Authorisation before access | No byte of Target memory is read or written before the command is authorised (ECSS 5.3.3.5, 5.4.3.5, 5.5.3.5). |
| P7 | Packet format of the SpaceWire port | All packet ports use the N-Char stream of the OpenWire core, so that the core connects to its packet ports without adaptation. |
| P8 | Verifiable in isolation | Each module has a specification and a testbench that drives only its ports. The RMAP model of the testbenches (packet builder, packet checker, CRC) is written independently of the RTL. |
| P9 | Reuse before design | A function available in Open Logic (FIFO, AXI master, AXI4-Lite slave, arbiter, ECC monitor) is instantiated, not rewritten. |
| P10 | No vendor code | The core has no vendor primitive. |

## 6 Architecture overview

```text
                     +-------------------------------------------------------------------------+
 S_Pkt (from SpW) -->| CO-1 demux --+--> TG-1 decoder --> TG-3 controller --> TG-4 memory ----+--> M_Axi (AXI4)
                     |              |        |              |   (TG-2 auth)      |              |
                     |              |        |              v                    v              |
 M_Pkt (to SpW)   <--| CO-2 mux <---+------- | ---------- TG-5 reply encoder <---+              |
                     |   ^   ^      |        |                                                  |
                     |   |   |      +--> IN-2 reply decoder --> IN-3 table --> M_Conf, M_RepData |
                     |   |   +---------- IN-1 command encoder <-------------- S_Req, S_ReqData  |
                     |   +-------------- S_User (user packets)                                   |
                     |              +--> M_User (packets of other protocols)                     |
                     |   MG-1 register file, MG-2 EDAC monitor <-------------- S_AxiLite, Irq    |
                     +-------------------------------------------------------------------------+
```

Received packets are dispatched by their Protocol Identifier and packet type: commands to the Target, replies to
the Initiator, packets of other protocols to the user port. The Target decodes a command, authorises it, accesses
the memory and encodes the reply; the Initiator encodes commands and decodes replies. The multiplexer merges
replies, commands and user packets into the transmitted packet stream without interleaving packets.

### Architecture decisions

| ID | Decision | Reason |
| --- | --- | --- |
| D1 | One clock domain `Clk` for all functions, including the memory interface and the register file | The SpaceWire port already crosses from its link clock to its user clock; a second crossing would add latency and FT crossings without benefit |
| D2 | The packet ports use the N-Char stream of the OpenWire core: `TData` 8 bit, the end of packet marker as a separate beat with `TLast` = '1' and `TData(0)` = '0' EOP, '1' EEP | Direct connection to the packet ports of the SpaceWire port; EOP and EEP are distinguishable, as RMAP requires (ECSS 5.3.3.4.3) |
| D3 | The Target executes one command at a time: decode, authorise, access, reply | RMAP over SpaceWire is limited by the link rate; sequential execution keeps the status of every command exact and makes read-modify-write atomic for RMAP |
| D4 | The Target memory is accessed through `olo_ft_axi_master_full` with byte addresses: the first data byte of a command is at the lowest address (little-endian byte lanes), the RMAP address bits above the AXI address width must be zero | Byte-exact unaligned accesses of any length without own alignment logic; ECC on the data buffers |
| D5 | Write data passes through one FT buffer: a verified write is buffered completely and written after the Data CRC and the end of the packet are checked; a non-verified write is committed in chunks of `ChunkBytes_g` bytes that are complete in the buffer | Verified writes as ECSS 5.3.3.6.4 requires; non-verified writes stream (ECSS 5.3.3.6.9), and an early EOP or EEP leaves the incomplete chunk, which contains the Data CRC, unwritten |
| D6 | A read reply is streamed: the header with status 0 is sent when the memory read starts, the data follows as it is read, a memory error ends the reply with an EEP | No buffer for read data; ECSS 5.4.3.10c.1 |
| D7 | A single-address access (increment bit clear) accesses one Word repeatedly: the address must be aligned to the Word and the length must be a multiple of it | The memory location width is chosen by the Target (ECSS 5.3.3.6.14 note); FIFOs and registers behind AXI are Word wide |
| D8 | Authorisation by two logical addresses and the default address 0xFE, a key, `Windows_g` address windows with read, write, verified-only write, read-modify-write and single-address permissions, and an optional external authorisation port | The Target user application of ECSS 5.3.3.5 in hardware; windows protect memory without software |
| D9 | One priority of the status codes: header checks (2, 12, 3, 11, 9, 10) before packet end errors (7, 5, 6), Data CRC (4), external authorisation (10) and memory errors (1) | ECSS 5.6.1d leaves the choice to the application; a fixed order makes the reply deterministic and testable |
| D10 | The Initiator takes a request descriptor and an 8-bit data stream and returns a confirmation descriptor and an 8-bit data stream; read data is passed on while it arrives and the confirmation tells whether it is valid | No buffer for reply data; the user discards data of a failed confirmation (ECSS 5.4.3.12) |
| D11 | An optional transaction table in the Initiator holds the outstanding commands, associates replies by TID, rejects duplicate TIDs and ends commands without reply after a timeout | Association of replies (ECSS 5.1.8, 5.3.3.9b) and the reply timeout of the Initiator user application (ECSS 4.3.1) in hardware |
| D12 | The protocol state machines have a defined recovery state, without TMR: the `when others` branch leads to it from an illegal state where the synthesis tool implements the state machine safe, and the reset input restarts it from any state | Same as OpenWire; RMAP recovers through the reply status and the Initiator timeout |

### Clock and reset

All blocks run in `Clk`. The reset input `Rst` is synchronous and high-active (Open Logic convention); the integrator
synchronises it to `Clk`, for example with `olo_base_reset_gen`.

### Internal interfaces

| Interface | Between | Payload | Protocol |
| --- | --- | --- | --- |
| N-Char stream | Packet ports, CO-1, CO-2, TG-1, TG-5, IN-1, IN-2 | 8-bit data character or end of packet marker (D2) | AXI4-Stream |
| Command header | TG-1 to TG-2 and TG-3 | Decoded header fields, header status | Valid / ready |
| Write data | TG-1 to TG-3 | Data bytes of a command, Data CRC result, end of packet class | Valid / ready |
| Memory command | TG-3 to TG-4 | Operation, address, length, single-address flag | Valid / ready |
| Reply request | TG-3 to TG-5 | Reply fields, status, data source | Valid / ready |
| Request descriptor | User to IN-1 | Command fields (ECSS 5.3.3.2b, 5.4.3.2b, 5.5.3.2b) | Valid / ready |
| Confirmation | IN-2 / IN-3 to user | TID, status, command, data length, local error | Valid / ready |
| Register bus | MG-1 and the user | Configuration, status, counters | AXI4-Lite (`olo_axi_lite_slave`) |

## 7 Building block specifications

The core has 12 building blocks in four groups. Each block lists its responsibility, the Open Logic entities it is
built from and the ECSS requirements it owns (P1: no clause is owned twice).

### 7.1 Target

| ID | Block | Responsibility | Open Logic | ECSS |
| --- | --- | --- | --- | --- |
| TG-1 | Command decoder | Header fields of a command (TLA to Header CRC, Reply Address of 0 to 12 bytes), Header CRC check, incomplete header, EEP after the header, classification of the data field (data, Data CRC, excess data) and of the end of the packet, Data CRC check | none | 5.1.2 to 5.1.5, 5.1.7 to 5.1.15, 5.2, 5.3.1, 5.4.1, 5.5.1, 5.3.3.4.1 to 5.3.3.4.5, 5.4.3.4.1 to 5.4.3.4.5, 5.5.3.4.1 to 5.5.3.4.5 |
| TG-2 | Authorisation | Packet type and command code, logical addresses, key, read-modify-write length, verify buffer size, address windows and permissions, alignment of single-address accesses, external authorisation port | none | 5.3.3.4.6 to 5.3.3.4.8, 5.3.3.5, 5.4.3.4.6 to 5.4.3.4.9, 5.4.3.5, 5.5.3.4.6, 5.5.3.4.7, 5.5.3.4.13, 5.5.3.4.15, 5.5.3.5, 5.7.2 |
| TG-3 | Command controller | Sequence of a command, write buffer (verified writes and chunks of non-verified writes), data and packet end errors, priority of the status codes, indication to the user application | `olo_ft_fifo_sync` | 5.3.3.6.2 to 5.3.3.6.13, 5.3.3.7, 5.4.3.7, 5.5.3.4.8 to 5.5.3.4.12, 5.5.3.4.14, 5.5.3.8, 5.6 |
| TG-4 | Memory access | Writes, reads and read-modify-writes on the AXI4 master, incrementing and single-address accesses, memory errors | `olo_ft_axi_master_full` | 5.3.3.6.1, 5.3.3.6.14, 5.3.3.10, 5.4.3.6, 5.4.3.10, 5.5.3.6, 5.5.3.7, 5.5.3.11 |
| TG-5 | Reply encoder | Reply SpaceWire Address from the Reply Address, reply header and Header CRC, read data and Data CRC, EOP or EEP | none | 5.1.6, 5.1.16, 5.1.17, 5.3.2, 5.4.2, 5.5.2, 5.3.3.8, 5.4.3.8, 5.5.3.9 |

### 7.2 Initiator

| ID | Block | Responsibility | Open Logic | ECSS |
| --- | --- | --- | --- | --- |
| IN-1 | Command encoder | Target SpaceWire Address, command header with Reply Address padded to the smallest number of words, Header CRC, data or data and mask, Data CRC | none | 5.1.1, 5.3.3.2, 5.3.3.3, 5.4.3.2, 5.4.3.3, 5.5.3.2, 5.5.3.3 |
| IN-2 | Reply decoder | Reply header and Header CRC, packet type and reserved bit, data length and Data CRC of the reply, confirmation with status and data | none | 5.3.3.9, 5.3.3.11, 5.3.3.12, 5.4.3.9, 5.4.3.11 to 5.4.3.13, 5.5.3.10, 5.5.3.12 to 5.5.3.14 |
| IN-3 | Transaction table | Outstanding commands with reply, association of replies by TID, duplicate TIDs, reply timeout | none | 5.1.8 |

### 7.3 Packet routing

| ID | Block | Responsibility | Open Logic | ECSS |
| --- | --- | --- | --- | --- |
| CO-1 | Packet demultiplexer | Dispatch by Protocol Identifier and packet type: commands to the Target, replies to the Initiator, other packets to the user port; commands at an Initiator-only node and replies at a Target-only node discarded | none | 5.1.3, 5.7.1 |
| CO-2 | Packet multiplexer | Merge of replies, commands and user packets, one complete packet at a time | `olo_base_arb_rr` | none (packet integrity of \[SPW\] 5.6.2) |

### 7.4 Management

| ID | Block | Responsibility | Open Logic | ECSS |
| --- | --- | --- | --- | --- |
| MG-1 | Register file | Configuration of the Target (logical addresses, key, windows) and the Initiator (timeout), status, error information, counters and interrupt, generated from one register description (`hdl/omap_mib/regs/omap_regs.yml`, `tools/regmap.py`) | `olo_axi_lite_slave` | 5.8 (product characteristics read back), error information gathering of 5.3 to 5.5 |
| MG-2 | EDAC monitor | Counts the SEC and DED events of every FT buffer, raises an interrupt, injects single and double errors for tests | `olo_ft_ecc_monitor` | none (fault tolerance, P5) |

## 8 Open Logic usage

| Open Logic entity | Used in | Purpose |
| --- | --- | --- |
| `olo_ft_axi_master_full` | TG-4 | AXI4 master with unaligned byte accesses, ECC on its data buffers |
| `olo_ft_fifo_sync` | TG-3 | Write buffer of the Target (verified writes, chunks of non-verified writes) |
| `olo_base_arb_rr` | CO-2 | Fair choice of the next packet source |
| `olo_axi_lite_slave` | MG-1 | AXI4-Lite access to the register file |
| `olo_ft_ecc_monitor` | MG-2 | SEC and DED counters per buffer, DED sticky flags |

### Gaps in Open Logic

| Gap | Resolution in this architecture |
| --- | --- |
| No RMAP CRC | The CRC of ECSS 5.2 is a function of `omap_pkg`, checked against the patterns of ECSS Annex A |
| No packet-atomic stream multiplexer | CO-2: `olo_base_arb_rr` with a packet lock |
| No TMR helper for protocol state machines | Recovery state of every state machine (D12) |

## 9 Verification architecture

The core is verified with VUnit and UVVM in a seven-phase module workflow (requirements, architecture, verification
plan, RTL, testbenches, verification, integration; see [conventions.md](conventions.md)). Every building block of
section 7 belongs to a module with its own specification, verification plan, testbench and verification report; core
tests cross the seams between the modules. Every test case names the requirements it verifies, and every requirement
names its ECSS clauses, so the traceability matrix of section 10 is checked by `tools/compliance.py`.

| Level | Scope | Bench | Checks |
| --- | --- | --- | --- |
| Unit | `omap_pkg` (CRC), Target, Initiator, register file | `<entity>_th.vhd` (clock, DUT, models) and `<entity>_tb.vhd` (VUnit runner, one `run("test_...")` per test of the verification plan) | UVVM checks, packets compared byte by byte with the RMAP model, memory compared with the AXI memory model |
| Core | Two cores connected by a packet network model: the Initiator of one core accesses the Target of the other | AXI4-Stream VVCs on the user ports, AXI4-Lite VVC on the register file, AXI memory model | Write, read and read-modify-write end to end, errors injected in the network, passthrough of other protocols, concurrency of Target and Initiator |

### Framework

- VUnit (`run.py`) discovers and runs every test and is the CI regression. UVVM supplies the verification building
  blocks: AXI4-Stream and AXI4-Lite VVCs, alert and log handling, `check_value` / `await_value`, randomisation.
- The RMAP model of the testbenches (`tb/omap_tb_rmap_pkg.vhd`) builds and checks commands and replies with its own
  implementation of ECSS 5.1 to 5.5; its CRC is the table method of ECSS Annex A.3, independent of the bitwise
  function of the RTL. The CRC test patterns of ECSS Annex A.4 are test cases.
- The AXI memory model (`tb/omap_tb_axi_ram.vhd`) is a behavioural AXI4 slave with random backpressure, error
  responses on configurable address ranges and backdoor access for checks.
- Simulator: GHDL for every test; QuestaSim for code coverage.

### Rules

- Tests observe ports and the register file only (P8).
- A failed check fails the test; a test cannot pass with a failed step.
- Negative tests inject the fault from the bench (corrupted CRC, early EOP, EEP, excess data, wrong key, memory
  error response, double error through the error injection of the FT buffers) and expect the status or the counter;
  never from an RTL mutation.
- Every commit passes the full regression.

## 10 Requirement traceability matrix

Every ECSS clause in the scope of section 1 has exactly one owner block. "First verified at" names the lowest
verification level at which the clause can be fully checked. The [compliance matrix](compliance.md), generated from this
table, the module specifications and the verification plans, lists the requirements and test cases of every clause.

| ECSS clause | Title | Owner | Also involved | First verified at |
| --- | --- | --- | --- | --- |
| 5.1.1 | Target SpaceWire Address field | IN-1 | CO-1 | Unit |
| 5.1.2 | Target Logical Address field | TG-1 | TG-2 | Unit |
| 5.1.3 | Protocol Identifier field | CO-1 | TG-1, IN-1 | Core |
| 5.1.4 | Instruction field | TG-1 | IN-1, IN-2 | Unit |
| 5.1.5 | Key field | TG-1 | TG-2 | Unit |
| 5.1.6 | Reply Address field | TG-5 | IN-1 | Unit |
| 5.1.7 to 5.1.15 | Initiator Logical Address to Data CRC fields | TG-1 | IN-1, IN-2 | Unit |
| 5.1.16 | Reply SpaceWire Address field | TG-5 |  | Unit |
| 5.1.17 | Status field | TG-5 | IN-2 | Unit |
| 5.2 | Cyclic Redundancy Code | TG-1 | all encoders and decoders (`omap_pkg`) | Unit |
| 5.3.1 | Write command format | TG-1 | IN-1 | Unit |
| 5.3.2 | Write reply format | TG-5 | IN-2 | Unit |
| 5.3.3.2, 5.3.3.3 | Write request and write command | IN-1 |  | Unit |
| 5.3.3.4 | Write data request | TG-1 (5.3.3.4.1 to 5.3.3.4.5), TG-2 (5.3.3.4.6 to 5.3.3.4.8) | CO-1 | Unit |
| 5.3.3.5 | Write data authorisation | TG-2 | MG-1 | Unit |
| 5.3.3.6 | Write data | TG-3 (5.3.3.6.2 to 5.3.3.6.13), TG-4 (5.3.3.6.1, 5.3.3.6.14) |  | Unit |
| 5.3.3.7 | Write data indication | TG-3 |  | Unit |
| 5.3.3.8 | Write reply | TG-5 |  | Unit |
| 5.3.3.9 | Write command complete confirmation | IN-2 | IN-3 | Unit |
| 5.3.3.10 | Write not OK | TG-4 | TG-3 | Unit |
| 5.3.3.11, 5.3.3.12 | Corrupted and invalid write reply | IN-2 |  | Unit |
| 5.4.1 | Read command format | TG-1 | IN-1 | Unit |
| 5.4.2 | Read reply format | TG-5 | IN-2 | Unit |
| 5.4.3.2, 5.4.3.3 | Read request and read command | IN-1 |  | Unit |
| 5.4.3.4 | Read data request | TG-1 (5.4.3.4.1 to 5.4.3.4.5), TG-2 (5.4.3.4.6 to 5.4.3.4.9) | CO-1 | Unit |
| 5.4.3.5 | Read data authorisation | TG-2 | MG-1 | Unit |
| 5.4.3.6 | Read data | TG-4 |  | Unit |
| 5.4.3.7 | Read data indication | TG-3 |  | Unit |
| 5.4.3.8 | Read reply | TG-5 |  | Unit |
| 5.4.3.9 | Read data confirmation | IN-2 | IN-3 | Unit |
| 5.4.3.10 | Read not OK | TG-4 | TG-5 | Unit |
| 5.4.3.11 to 5.4.3.13 | Read reply header error, data error, invalid reply | IN-2 |  | Unit |
| 5.5.1 | Read-modify-write command format | TG-1 | IN-1 | Unit |
| 5.5.2 | Read-modify-write reply format | TG-5 | IN-2 | Unit |
| 5.5.3.2, 5.5.3.3 | Read-modify-write request and command | IN-1 |  | Unit |
| 5.5.3.4 | Read-modify-write data request | TG-1 (5.5.3.4.1 to 5.5.3.4.5), TG-2 (5.5.3.4.6, 5.5.3.4.7, 5.5.3.4.13, 5.5.3.4.15), TG-3 (5.5.3.4.8 to 5.5.3.4.12, 5.5.3.4.14) | CO-1 | Unit |
| 5.5.3.5 | Read-modify-write authorisation | TG-2 | MG-1 | Unit |
| 5.5.3.6, 5.5.3.7 | Read data, write data | TG-4 |  | Unit |
| 5.5.3.8 | Read-modify-write data indication | TG-3 |  | Unit |
| 5.5.3.9 | Read-modify-write reply | TG-5 |  | Unit |
| 5.5.3.10 | Read-modify-write complete confirmation | IN-2 | IN-3 | Unit |
| 5.5.3.11 | Read and write not OK | TG-4 | TG-5 | Unit |
| 5.5.3.12 to 5.5.3.14 | Read-modify-write reply header error, data error, invalid reply | IN-2 |  | Unit |
| 5.6 | Error and status codes | TG-3 | TG-2, TG-5 | Unit |
| 5.7.1 | Limited functionality nodes | CO-1 | MG-1 | Core |
| 5.7.2 | Partial implementations | TG-2 |  | Unit |
| 5.8 | RMAP conformance | MG-1 | user guide | Core |

## 11 Development plan

1. Foundations: repository, common package with the RMAP CRC, verification components (RMAP model, AXI memory
   model), regression and CI.
2. Target (TG-1 to TG-5) with unit tests against the RMAP model and the AXI memory model.
3. Initiator (IN-1 to IN-3) with unit tests against the RMAP model.
4. Register file (MG-1, MG-2) with the generated register map.
5. Core top level (CO-1, CO-2) with core tests of two cores and the compliance matrix, the synthesizability check and
   the user guide.
