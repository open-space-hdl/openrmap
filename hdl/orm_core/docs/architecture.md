# orm_core: Architecture and Design Description

## 1. Block diagram

```text
                +---------------------------------------------------------------------------+
 S_Pkt -------->| CO-1 orm_core_demux --+--> orm_tgt (Target_g) -----> M_Axi, Auth, Ind     |
                |   (3-character        |        | replies                                  |
                |    lookahead)         |        v                                          |
 M_Pkt <--------| CO-2 orm_core_mux <---+------- + <--- orm_ini (Initiator_g) <-- S_Req,    |
                |   (olo_base_arb_rr,   |        commands      | replies     S_ReqData      |
                |    packet lock)       +----------------------+--> M_Conf, M_RepData       |
 M_User <-------|   user packets <------+                                                   |
 S_User ------->|   user packets ------> CO-2                                               |
                |   orm_mib: configuration, status, counters, EDAC <-- S_AxiLite, --> Irq   |
                +---------------------------------------------------------------------------+
```

All blocks run in `Clk`. Without target or initiator the generate branch drives their outputs to zero and accepts
every character offered to them; without user port the user packets are discarded by the demultiplexer and
`S_User_TReady` stays '0'.

## 2. Packet demultiplexer (CO-1, `orm_core_demux`)

| State | Action |
| --- | --- |
| Head | Accepts up to three characters into a buffer, or fewer when the end of packet marker comes first |
| Decide | Destination from the buffered characters (table below); event to the register file |
| Replay | The buffered characters to the destination |
| Pass | The rest of the packet from the input to the destination, up to the end of packet marker |
| Drop | The rest of a discarded packet |

| First characters | Destination |
| --- | --- |
| Fewer than 2 data characters, or second character other than 0x01 | User port; discarded without user port (event "discarded") |
| 0x01 and packet type 0b00 | Initiator; target in a target-only node |
| 0x01 and packet type 0b01 or 0b1x | Target; discarded in an initiator-only node (event "command received") |
| 0x01, end of packet before the instruction | Target; initiator in an initiator-only node |

The lookahead delays a packet by its first three characters and one decision cycle; the rest of a packet passes at
one character per cycle. The recovery state of the state machine (D12) is Drop: it discards up to the next end of
packet marker.

## 3. Packet multiplexer (CO-2, `orm_core_mux`)

`olo_base_arb_rr` sees the valid signals of the three sources while no packet is being sent. Its grant is registered
as the selected source, which is passed to the output until the handshake of its end of packet marker; then the
arbiter chooses again. A packet start costs one idle cycle.

## 4. Link stall with mutual initiators

A target receives the end of a command only when its controller is free, and its controller is free only when the
reply of the previous command has been sent. A reply waits while the multiplexer sends a command of the own initiator.
When two nodes are initiator and target of each other and both have several commands outstanding, a cycle can form:
both multiplexers send a command, the end of which the other target does not take because that target waits to send
a reply behind the command of its own node. With one outstanding command with reply per initiator the cycle cannot
form: a command with reply is sent only after the reply to the previous command of the same initiator has arrived, so
the command that a multiplexer sends never waits for a reply that is queued behind it. Commands without reply do not
take part in the cycle, because the target takes them completely without waiting for its output. The user guide
states the rule.

## 5. Resources and timing

The demultiplexer holds three characters and a state machine; the multiplexer a three-bit selection. The paths from
the input to the outputs of the demultiplexer and from the sources to `M_Pkt` are combinational within one cycle, as
the AXI4-Stream conventions of Open Logic allow.
