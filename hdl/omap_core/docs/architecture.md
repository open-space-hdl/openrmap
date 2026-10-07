# omap_core: Architecture and Design Description

## 1. Block diagram

```text
                +---------------------------------------------------------------------------+
 S_Pkt -------->| CO-1 omap_core_demux --+--> omap_target (Target_g) -----> M_Axi, Auth, Ind     |
                |   (3-character        |        | replies                                  |
                |    lookahead)         |        v                                          |
 M_Pkt <--------| CO-2 omap_core_mux <---+------- + <--- omap_initiator (Initiator_g) <-- S_Req,    |
                |   (olo_base_arb_rr,   |        commands      | replies     S_ReqData      |
                |    packet lock)       +----------------------+--> M_Conf, M_RepData       |
 M_User <-------|   user packets <------+                                                   |
 S_User ------->|   user packets ------> CO-2                                               |
                |   omap_mib: configuration, status, counters, EDAC <-- S_AxiLite, --> Irq   |
                +---------------------------------------------------------------------------+
```

All blocks run in `Clk`. Without Target or Initiator the generate branch drives their outputs to zero and accepts
every character offered to them; without user port the user packets are discarded by the demultiplexer and
`S_User_TReady` stays '0'.

## 2. Packet demultiplexer (CO-1, `omap_core_demux`)

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
| 0x01 and packet type 0b00 | Initiator; Target in a Target-only node |
| 0x01 and packet type 0b01 or 0b1x | Target; discarded in an Initiator-only node (event "command received") |
| 0x01, end of packet before the instruction | Target; Initiator in an Initiator-only node |

The lookahead delays a packet by its first three characters and one decision cycle; the rest of a packet passes at
one character per cycle. The recovery state of the state machine (D12) is Drop: it discards up to the next end of
packet marker.

## 3. Packet multiplexer (CO-2, `omap_core_mux`)

`olo_base_arb_rr` sees the valid signals of the three sources while no packet is being sent. Its grant is registered
as the selected source, which is passed to the output until the handshake of its end of packet marker; then the
arbiter chooses again. A packet start costs one idle cycle.

## 4. Link stall with mutual Initiators

A Target receives the end of a command only when its controller is free, and its controller is free only when the
reply of the previous command has been sent. A reply waits while the multiplexer sends a command of the own Initiator.
When two nodes are Initiator and Target of each other and both have several commands outstanding, a cycle can form:
both multiplexers send a command, the end of which the other Target does not take because that Target waits to send
a reply behind the command of its own node. With one outstanding command with reply per Initiator the cycle cannot
form: a command with reply is sent only after the reply to the previous command of the same Initiator has arrived, so
the command that a multiplexer sends never waits for a reply that is queued behind it. Commands without reply do not
take part in the cycle, because the Target takes them completely without waiting for its output. The user guide
states the rule.

## 5. Resources and timing

The demultiplexer holds three characters and a state machine; the multiplexer a three-bit selection. The paths from
the input to the outputs of the demultiplexer and from the sources to `M_Pkt` are combinational within one cycle, as
the AXI4-Stream conventions of Open Logic allow.
