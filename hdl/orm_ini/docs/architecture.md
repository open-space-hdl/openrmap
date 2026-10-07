# orm_ini: Architecture and Design Description

## 1. Overview

```text
 S_Req, S_Data --> IN-1 orm_ini_tx --> M_Cmd
                       |   ^ register / TID in use / free entry
                       v   |
                     IN-3 orm_ini_tt --- timeout ---+
                       ^   | lookup / remove         |
                       |   v                         v
 S_Rep -------------> IN-2 orm_ini_rx --> M_Data   confirmation selection --> M_Conf
                                      \--------------------^      ^ rejection (IN-1)
```

All blocks run in `Clk`. Confirmations come from three sources: replies (IN-2), rejected requests (IN-1) and timeouts
(IN-3). A source is selected when the output is free, in this order, and kept until its handshake.

## 2. Command encoder (IN-1, `orm_ini_tx`)

| State | Action |
| --- | --- |
| Idle | Request taken: Reply Address Length = ceil(length / 4), the Reply Address shifted by the number of padding bytes, instruction 0b01, command field, Reply Address Length |
| Check | Request with reply: Transaction Identifier in use: Reject; free entry: registration, Path; otherwise wait. Request without reply: Path |
| Reject, Drop | Confirmation with "Transaction Identifier in use", then the data of the request is consumed |
| Path | Target SpaceWire Address bytes, first byte first |
| Head, HeadCrc | Header bytes from the Target Logical Address to the Data Length, Header CRC computed on the fly |
| Data, DataCrc | Data Length bytes of the data stream and the Data CRC (write and read-modify-write) |
| Eop | End of packet marker |

The output is a register that takes a character when it is empty or being read.

## 3. Reply decoder (IN-2, `orm_ini_rx`)

The decoder counts the header characters. The instruction (third character) selects the format: read format for the
read and read-modify-write command codes, write format otherwise; the Header CRC follows after 7 or 11 characters.
The packet type, the reserved bit and the reply bit are checked when the instruction arrives. With an intact header
the transaction table is asked for the Transaction Identifier; a hit with the same command field and Reply Address
Length leads to the data field, otherwise the reply is discarded as unexpected.

Data bytes (read format, up to the Data Length) pass through a hold register of two bytes: a byte is passed on when
the second byte after it arrives. At the end of the packet the held bytes are passed on and the last one carries
`TLast`; in a reply that ended before its Data CRC the newest held byte is taken as the Data CRC and dropped. The
character after the data is compared with the Data CRC; further characters set the excess flag. The confirmation
follows the last data byte; on its handshake the entry is removed from the table.

| End of the data field | Local error |
| --- | --- |
| EOP immediately after a correct Data CRC (read format) or after the Header CRC (write format) | none |
| EEP, early EOP, excess characters, Data CRC error | data error |

## 4. Transaction table (IN-3, `orm_ini_tt`)

Each of the `Transactions_g` entries holds a valid flag, an expired flag, the Transaction Identifier, the instruction
and a 16-bit timer. All comparisons with a Transaction Identifier are parallel. A prescaler gives a tick every
`Cfg_TickCycles` + 1 cycles; at every tick the timer of every valid entry counts down and the entry expires at the end
of `Cfg_Timeout` ticks. The lowest expired entry is presented as a timeout confirmation and removed with its handshake;
an expired entry no longer matches replies, so a late reply is unexpected. A free entry is the lowest invalid one.

## 5. Resources and timing

The transaction table has `Transactions_g` 16-bit comparators for each of the three Transaction Identifier inputs.
With the default of 8 entries this is a small amount of logic; the comparators feed registered state only.
