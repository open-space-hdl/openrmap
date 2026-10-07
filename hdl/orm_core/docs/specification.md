# orm_core: Specification

## 1. Overview

`orm_core` is the top level of OpenRMAP: the RMAP target (`orm_tgt`), the RMAP initiator (`orm_ini`) and the
register file (`orm_mib`), connected to the packet ports of a SpaceWire port by the packet demultiplexer (CO-1,
`orm_core_demux`) and the packet multiplexer (CO-2, `orm_core_mux`). Generics select the node type and the user port
for packets of other protocols.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| CO-IF-01 | The core shall receive and send packets as N-Char streams (`TData` 8 bit, end of packet marker as a separate beat with `TLast` = '1', `TData(0)` = '0' EOP, '1' EEP), the packet ports of a SpaceWire port. | none (D2) |
| CO-IF-02 | With `Passthrough_g` the core shall provide a user port that receives and sends packets of other protocols as N-Char streams. | none (\[PID\]) |
| CO-IF-03 | The core shall provide the memory interface, the external authorisation port and the indications of the target, the request, confirmation and data interfaces of the initiator, and the AXI4-Lite port and interrupt of the register file. | 5.3.3, 5.4.3, 5.5.3 |

### 2.2 Packet demultiplexer (CO-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| CO-DM-01 | A received packet whose second character is the Protocol Identifier 0x01 shall be passed to the target when its packet type is command (0b01) or reserved (0b1x), and to the initiator when its packet type is reply (0b00). A packet that ends before its instruction shall be passed to the target, in an initiator-only node to the initiator. | 5.1.3, 5.1.4 |
| CO-DM-02 | A packet with another Protocol Identifier, or one that ends before its second character, shall be passed to the user port; without user port it shall be discarded and counted. | 5.1.3 |
| CO-DM-03 | In an initiator-only node a command shall be discarded and the error "Command Received by Initiator" recorded. | 5.7.1.2b, 5.7.1.2c |
| CO-DM-04 | In a target-only node a reply shall be passed to the target, which discards it and records the error "Reply Received by Target". | 5.7.1.3b, 5.7.1.3c |
| CO-DM-05 | Every packet shall reach one destination complete and unchanged, including its end of packet marker. | none |

### 2.3 Packet multiplexer (CO-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| CO-MX-01 | The replies of the target, the commands of the initiator and the packets of the user port shall be sent one complete packet at a time; the next source is chosen round robin among the sources with a packet waiting. | none (\[SPW\] 5.6.2) |

### 2.4 Node

| ID | Requirement | ECSS |
| --- | --- | --- |
| CO-NO-01 | The core shall implement a node that is target and initiator, target only or initiator only (`Target_g`, `Initiator_g`). | 5.7.1.1, 5.7.1.2a, 5.7.1.3a |
| CO-NO-02 | The node type, the user port and the product characteristics fixed by generics shall be readable in the register file; the conformance statement and the product characteristics tables are in the user guide. | 5.8.1, 5.8.2 |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `Target_g`, `Initiator_g` | true | at least one true | Node type |
| `Passthrough_g` | true | | User port for packets of other protocols |
| `AxiAddrWidth_g`, `AxiDataWidth_g`, `AxiMaxBeats_g` | 32, 32, 16 | 12 to 40, 8 to 1024, 1 to 256 | Memory interface of the target |
| `BufferBytes_g`, `ChunkBytes_g` | 256, 32 | 1 to 65535 | Verify buffer and chunk of non-verified writes |
| `Windows_g`, `ExtAuth_g` | 4, false | 0 to 8 | Address windows and external authorisation of the target |
| `TgtAddrBytes_g`, `Transactions_g` | 8, 8 | 0 to 16, 0 to 64 | Target SpaceWire Address and transaction table of the initiator |
| `La0_g`, `La1_g`, `DefLaEn_g`, `Key_g`, `TickCycles_g`, `Timeout_g`, `WinInit_g` | | | Reset values of the register file |

## 4. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 5.1.3 | A packet is RMAP when its second character is 0x01. Packets with other identifiers, including the extended protocol identifier 0x00, belong to other protocols (\[PID\]). |
| 5.1.4 | A packet with a reserved packet type (0b1x) goes to the target, which discards it without reply (ECSS 5.3.3.4.6). In an initiator-only node it is discarded as a command. |
| 5.7.1.2c, 5.7.1.3c | "Should be recorded": counters in the register file (INI_CNT4.CMD_RX, TGT_CNT_ERR6.REPLY_RX) and the event flags PKT_DISCARD and TGT_DISCARD. |

## 5. Integration constraints

| Constraint | Reason |
| --- | --- |
| Two nodes that are initiator and target of each other on one link shall have at most one outstanding command with reply per initiator (`Transactions_g` = 1), or the receive path of each node shall buffer the commands that the other node can have outstanding | A target replies only after it has received its command and receives the next command only after its reply; a reply waits for a command of the own initiator that is being sent. With several outstanding commands in both directions both targets can wait for their replies while each link carries a command that the other target does not take: the link stalls. One outstanding command per initiator guarantees that a command arrives at an idle target. |
| The user shall take the reply data, the confirmations and the packets of the user port | A stalled output of the demultiplexer stalls the link |
