# omap_target: Specification

## 1. Overview

`omap_target` is the RMAP Target (blocks TG-1 to TG-5 of the architecture): it receives RMAP commands on an N-Char
stream, checks and authorises them, executes write, read and read-modify-write commands on the Target memory through
an AXI4 master and sends the replies on a second N-Char stream. It executes one command at a time (architecture D3).

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| TG-IF-01 | The Target shall receive commands and send replies as N-Char streams (`TData` 8 bit, end of packet marker as a separate beat with `TLast` = '1', `TData(0)` = '0' EOP, '1' EEP). The first character of a command is the Target Logical Address. | 5.1.1a note, 5.3.3.4.1 |
| TG-IF-02 | The Target shall access its memory through an AXI4 master with byte addresses (40-bit RMAP address, of which the bits above the AXI address width are zero). The first data byte of a command is at the lowest address. | 5.1.9, 5.1.10, 5.1.13 note |
| TG-IF-03 | The Target shall take its configuration (logical addresses, key, address windows) from the register file and report every checked command and every discarded packet as events. | 5.3.3.5, error information gathering of 5.3.3, 5.4.3, 5.5.3 |
| TG-IF-04 | With `ExtAuth_g` the Target shall ask an external authorisation port for every command that passes the internal checks and reject it when the port does not accept it. | 5.3.3.5.1, 5.4.3.5.1, 5.5.3.5.1 |
| TG-IF-05 | The Target shall indicate every executed or rejected command with a reply-capable header to the user application with its instruction, address, length, Transaction Identifier and status. | 5.3.3.7, 5.4.3.7, 5.5.3.8 |
| TG-IF-06 | The reset input shall return the Target from any state to the reception of a new command; the next command after the reset is executed normally. | none (D12) |

### 2.2 Command decoding (TG-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| TG-RX-01 | The Target shall decode the command header: Target Logical Address, Protocol Identifier, Instruction, Key, Reply Address of 0, 4, 8 or 12 bytes as the Reply Address Length field defines, Initiator Logical Address, Transaction Identifier (most significant byte first), Extended Address, Address (most significant byte first), Data Length (most significant byte first) and Header CRC. | 5.1.2 to 5.1.12, 5.3.1, 5.4.1, 5.5.1 |
| TG-RX-02 | The Target shall check the Header CRC over the header from the Target Logical Address to the byte before the Header CRC; a header with a CRC error shall be discarded with the rest of its packet, without reply. | 5.2, 5.3.3.4.4, 5.3.3.4.5, 5.4.3.4.4, 5.4.3.4.5, 5.5.3.4.4, 5.5.3.4.5 |
| TG-RX-03 | A packet that ends (EOP or EEP) before the Header CRC shall be discarded without reply. | 5.3.3.4.2, 5.4.3.4.2, 5.5.3.4.2 |
| TG-RX-04 | A packet that ends with an EEP immediately after the Header CRC shall be discarded without reply. | 5.3.3.4.3, 5.4.3.4.3, 5.5.3.4.3 |
| TG-RX-05 | For write and read-modify-write commands the Target shall take the Data Length bytes after the header as the data field, the next byte as the Data CRC and check the Data CRC over the data field; it shall classify the end of the packet as complete (EOP after the Data CRC), early (EOP before the Data CRC), with excess data (characters after the Data CRC) or with an EEP. For read commands every character after the header is excess data. | 5.1.13 to 5.1.15, 5.2, 5.3.1.14 to 5.3.1.16, 5.4.1.14, 5.5.1.14 to 5.5.1.17 |
| TG-RX-06 | A packet with packet type 0b00 (a reply) shall be discarded by the Target. | 5.7.1.3b |

### 2.3 Authorisation (TG-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| TG-AU-01 | A command with a reserved packet type (0b10, 0b11) shall be discarded without reply. | 5.3.3.4.6a, 5.4.3.4.6a, 5.5.3.4.6a |
| TG-AU-02 | A command with an invalid command code shall not be executed; the status is "unused RMAP packet type or command code" (2). | 5.3.3.4.7, 5.4.3.4.7, 5.5.3.4.7 |
| TG-AU-03 | A command whose Target Logical Address is not one of the two configured logical addresses or, when enabled, the default address 0xFE shall not be executed; the status is "invalid Target Logical Address" (12). | 5.3.3.5.3, 5.4.3.5.3, 5.5.3.5.3 |
| TG-AU-04 | A command whose key differs from the configured key, when the key check is enabled, shall not be executed; the status is "invalid key" (3). | 5.1.5, 5.3.3.5.2, 5.4.3.5.2, 5.5.3.5.2 |
| TG-AU-05 | A read-modify-write command with a Data Length other than 0, 2, 4, 6 or 8 shall not be executed; the status is "RMW Data Length error" (11). | 5.5.1.12d, 5.5.3.4.13 |
| TG-AU-06 | A verified write command with a Data Length larger than the verify buffer (`BufferBytes_g`) shall not be executed; the status is "verify buffer overrun" (9). | 5.3.3.6.3 |
| TG-AU-07 | A command shall be authorised only when all bytes it accesses lie in one enabled address window that permits its kind (read, write, verified-only write, read-modify-write, single address) and within the AXI address range, and when a single-address access is aligned to the memory word and has a length that is a multiple of it; otherwise the status is "RMAP command not implemented or not authorised" (10). | 5.3.3.5.4, 5.4.3.5.4, 5.5.3.5.4, 5.7.2 |
| TG-AU-08 | When more than one status applies, the Target shall report the first one in the order of the architecture decision D9: 2, 12, 3, 11, 9, 10 (header checks), then 7, 5, 6 (end of the packet), 4 (Data CRC), 10 (external authorisation), 1 (memory). | 5.6.1d, 5.6.1e |

### 2.4 Command execution (TG-3, TG-4)

| ID | Requirement | ECSS |
| --- | --- | --- |
| TG-EX-01 | A verified write shall be buffered and written to memory only when the Data CRC is correct and the packet ends with an EOP immediately after the Data CRC; otherwise no byte shall be written and the status is 7, 5, 6 or 4. | 5.3.3.6.2, 5.3.3.6.4 to 5.3.3.6.8 |
| TG-EX-02 | A non-verified write shall be written while it is received, in chunks of `ChunkBytes_g` bytes that are complete in the buffer; at an early EOP or an EEP the incomplete chunk shall not be written (status 5 or 7); with excess data the Data Length bytes shall be written and the rest discarded (status 6); a Data CRC error shall be reported after the data is written (status 4). | 5.3.3.6.9 to 5.3.3.6.13 |
| TG-EX-03 | A write with the increment bit set shall write sequential addresses; with the increment bit clear every memory word of the data shall be written to the same address. | 5.3.3.6.14 |
| TG-EX-04 | A read command shall be executed only when the packet ends with an EOP immediately after the header; data characters after the header give the status "too much data" (6) without execution. With the increment bit set sequential addresses shall be read, with the increment bit clear the same address for every memory word. | 5.4.3.4.8, 5.4.3.6 |
| TG-EX-05 | A read-modify-write command shall be buffered and checked (Data CRC, length, end of packet) before it is authorised externally; it shall then read the n = Data Length / 2 bytes at the address, write (mask and data) or (not mask and read data) to the same bytes and return the bytes read. | 5.5.3.4.8 to 5.5.3.4.12, 5.5.3.4.14, 5.5.3.4.15, 5.5.3.6, 5.5.3.7 |
| TG-EX-06 | An error response of the memory, or a double error in a data buffer, during a write or a read-modify-write shall give the status "general error code" (1); during a read the reply shall end with an EEP after the data. | 5.3.3.10, 5.4.3.10, 5.5.3.11 |
| TG-EX-07 | A command of length zero shall access no memory and complete with status 0. | 5.3.1.12 note, 5.4.1.12 note |

### 2.5 Replies (TG-5)

| ID | Requirement | ECSS |
| --- | --- | --- |
| TG-TX-01 | A reply shall be sent when the Reply bit is set and the header was received intact (TG-RX-02 to TG-RX-04, TG-AU-01 not applicable), and no reply otherwise. | 5.3.3.8, 5.4.3.8, 5.5.3.9 |
| TG-TX-02 | The Reply SpaceWire Address shall be the Reply Address field without its leading 0x00 bytes; a field of only 0x00 bytes with a non-zero Reply Address Length gives a single 0x00. | 5.1.6c to e, 5.1.16 |
| TG-TX-03 | A write reply shall consist of the Reply SpaceWire Address, Initiator Logical Address, Protocol Identifier, Instruction with packet type 0b00 and the command and Reply Address Length of the command, Status, Target Logical Address of the command, Transaction Identifier, Header CRC and EOP. | 5.3.2, 5.1.17 |
| TG-TX-04 | A read and a read-modify-write reply shall consist of the fields of a write reply before the Header CRC, a reserved byte 0x00, the Data Length (the length read; n for a read-modify-write), the Header CRC, the data, the Data CRC and EOP; a reply with an error status before the data has no data and a Data CRC of 0x00. | 5.4.2, 5.5.2, 5.2f |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `AxiAddrWidth_g` | 32 | 12 to 40 | AXI address width |
| `AxiDataWidth_g` | 32 | 8 to 1024, power of 2 | AXI data width; the memory word of single-address accesses |
| `AxiMaxBeats_g` | 16 | 1 to 256 | Maximum beats of an AXI burst |
| `BufferBytes_g` | 256 | 8 or more, power of 2 | Verify buffer: maximum Data Length of a verified write |
| `ChunkBytes_g` | 32 | Multiple of the memory word, at most `BufferBytes_g` / 2 | Chunk of a non-verified write |
| `Windows_g` | 4 | 0 to 8 | Number of address windows; 0 authorises every address in the AXI range |
| `ExtAuth_g` | false | boolean | External authorisation port |

## 4. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 5.3.3.4.6c, 5.4.3.4.6c, 5.5.3.4.6c | The optional reply to a reserved packet type is not sent. |
| 5.3.3.6.11 note | Bytes of an incomplete chunk, which include a possible Data CRC, are not written. |
| 5.4.3.10c, 5.5.3.11c | A read reply is streamed, so a memory error ends it with an EEP (option 1). A read-modify-write reply is assembled after the access and carries status 1 with the data read, its Data CRC and an EOP (option 2); a read error gives no data. |
| 5.5.3.6 note | Read-modify-write is atomic with respect to other RMAP commands of the Target (one command at a time); AXI4 has no locked transfers, so it is not atomic with respect to other bus masters. |
| 5.6.1d | The status priority of TG-AU-08. |
