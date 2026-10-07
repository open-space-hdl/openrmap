# orm_ini: Specification

## 1. Overview

`orm_ini` is the RMAP initiator (blocks IN-1 to IN-3 of the architecture): it builds commands from request
descriptors and a data stream, sends them on an N-Char stream, decodes the replies from a second N-Char stream and
returns confirmations and the data read. An optional transaction table associates the replies with the outstanding
commands.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| IN-IF-01 | The initiator shall take a request descriptor with the parameters of a write, read or read-modify-write request (command field, Target SpaceWire Address of up to `TgtAddrBytes_g` bytes, Target Logical Address, key, Reply Address of up to 12 bytes, Initiator Logical Address, Transaction Identifier, 40-bit address, Data Length) and, for write and read-modify-write requests, Data Length bytes of data (data followed by mask) on an 8-bit stream. | 5.3.3.2, 5.4.3.2, 5.5.3.2 |
| IN-IF-02 | The initiator shall send commands and receive replies as N-Char streams (`TData` 8 bit, end of packet marker as a separate beat with `TLast` = '1', `TData(0)` = '0' EOP, '1' EEP); the first character of a reply is the Initiator Logical Address. | 5.1.16 |
| IN-IF-03 | The initiator shall return one confirmation per reply with an intact header (Transaction Identifier, instruction, status, Data Length, local error) and the data of read and read-modify-write replies on an 8-bit stream whose last byte carries `TLast`. | 5.3.3.9, 5.4.3.9, 5.5.3.10 |
| IN-IF-04 | The initiator shall report sent commands, confirmed replies, discarded replies, data errors, timeouts and rejected requests as events, and the number of outstanding commands. | error information gathering of 5.3.3, 5.4.3, 5.5.3 |

### 2.2 Command encoder (IN-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| IN-TX-01 | A command shall consist of the Target SpaceWire Address, the Target Logical Address, the Protocol Identifier 0x01, the instruction (packet type 0b01, the command field of the request, the Reply Address Length), the key, the Reply Address field, the Initiator Logical Address, the Transaction Identifier, the Extended Address, the Address and the Data Length (most significant bytes first) and the Header CRC over the header from the Target Logical Address. | 5.1.1 to 5.1.12, 5.3.1, 5.4.1, 5.5.1 |
| IN-TX-02 | The Reply Address Length shall be the smallest number of 32-bit words that holds the Reply Address bytes of the request; the Reply Address field shall be the bytes preceded by 0x00 bytes up to that number of words. | 5.1.6, 5.3.1.5.4, 5.4.1.5.4, 5.5.1.5.4 |
| IN-TX-03 | Write and read-modify-write commands shall carry the Data Length bytes of the data stream and the Data CRC over them (0x00 for no data), followed by an EOP; read commands end with an EOP after the Header CRC. | 5.1.13 to 5.1.15, 5.2f, 5.3.3.3, 5.4.3.3, 5.5.3.3 |

### 2.3 Reply decoder (IN-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| IN-RX-01 | The initiator shall decode write replies (Initiator Logical Address, Protocol Identifier, instruction, status, Target Logical Address, Transaction Identifier, Header CRC) and read and read-modify-write replies (the same fields, a reserved byte and the Data Length before the Header CRC, then data and Data CRC). The format follows from the command field of the instruction. | 5.3.2, 5.4.2, 5.5.2 |
| IN-RX-02 | A reply with a Header CRC error, an end of packet before the Header CRC, the reserved bit or the command bit set in the instruction, or the reply bit clear, shall be discarded without confirmation. | 5.3.3.11, 5.3.3.12, 5.4.3.11, 5.4.3.13, 5.5.3.12, 5.5.3.14 |
| IN-RX-03 | A reply with an intact header whose data field is corrupted (fewer or more bytes than the Data Length, Data CRC error, EEP; for a write reply any character after the Header CRC or an EEP) shall be confirmed with the local error "data error"; its data is invalid. | 5.3.3.11, 5.4.3.12, 5.5.3.13 |
| IN-RX-04 | The data of read and read-modify-write replies shall be passed on while the reply arrives, up to the Data Length; the last byte passed on carries `TLast`. In a reply that ends before its Data CRC the last byte received is taken as its Data CRC. | 5.4.3.9 note, 5.5.3.10 note |

### 2.4 Transaction table (IN-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| IN-TT-01 | With `Transactions_g` > 0 every command with the reply bit set shall be registered with its Transaction Identifier and instruction; a reply shall be confirmed only when a registered command has its Transaction Identifier and its command field and Reply Address Length, otherwise it is discarded ("unexpected reply"). | 5.1.8, 5.3.3.9b, 5.4.3.9b, 5.5.3.10b |
| IN-TT-02 | A request with reply whose Transaction Identifier is registered shall not be sent; it shall be confirmed with the local error "Transaction Identifier in use". A request with reply shall wait while all entries are in use. | 5.1.8 note |
| IN-TT-03 | A registered command whose reply has not arrived after the configured number of ticks shall be confirmed with the local error "timeout" and removed; a timeout of zero disables it. | 4.3.1 |
| IN-TT-04 | With `Transactions_g` = 0 every reply with an intact header shall be confirmed. | 5.3.3.9 |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `TgtAddrBytes_g` | 8 | 0 to 16 | Maximum length of the Target SpaceWire Address |
| `Transactions_g` | 8 | 0 to 64 | Entries of the transaction table; 0 without table |

| Configuration input | Description |
| --- | --- |
| `Cfg_TickCycles` | Tick period minus one in clock cycles |
| `Cfg_Timeout` | Reply timeout in ticks; 0 disables the timeout |

## 4. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 5.3.3.12, 5.4.3.13, 5.5.3.14 | The text discards a reply "with the command/reply bit clear"; a reply has this bit clear by definition. The initiator discards a reply with the command bit set (a command) or the reserved bit set. |
| 5.4.3.12 | The data of a reply is passed on while it arrives; "discard the reply" means that the confirmation reports the data error and the data is not to be used. |
| 4.3.1 | The reply timeout of the initiator user application is implemented in the transaction table. |
