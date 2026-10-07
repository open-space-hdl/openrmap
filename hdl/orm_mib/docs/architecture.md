# orm_mib: Architecture and Design Description

## 1. Block diagram

```text
 AXI4-Lite --> olo_axi_lite_slave --> Rb_Wr, Rb_Rd --> MG-1 register file --> Cfg_* (target, initiator)
               (10-bit address)  <-- Rb_RdData   <--   configuration       <-- Tgt_Ind*, Tgt_Evt*
                                                       last command        <-- Ini_Evt*, Ini_Open
                                                       counters, flags     <-- Pkt_Evt*
 Irq <------------------------------------------------ interrupt
                                                       MG-2 olo_ft_ecc_monitor <-- Ecc_Sec, Ecc_Ded (3 channels)
                                                       injection commands      --> Inj_Valid, Inj_Double
```

All of `orm_mib` runs in `Clk`, the clock of the core.

## 2. Register file (MG-1)

The register map is in [register_map.md](register_map.md). The file is one two-process entity:

| Behaviour | Implementation |
| --- | --- |
| Write | Decoded from the word address in the cycle of `Rb_Wr`; byte enables are not used |
| Read | Data selected in the cycle of `Rb_Rd` and registered (`Rb_RdValid` one cycle after `Rb_Rd`) |
| Commands (W1, WO) | One-cycle pulses: ECC injection, ECC clear, ECC channel clear |
| Sticky flags (W1C) | `flags := (flags AND NOT written) OR events`: an event in the cycle of a clear is kept |
| Counters (RC) | 16 bits, saturating; a write clears both counters of the register, then the increment of the same cycle is applied |
| Last command | Registered with every indication of the target (`Tgt_IndValid`) |
| Status counters | The status of an indication selects its counter; status 0 selects the counter of the command kind (`cmdKind` of the command code) |
| Windows | Registers of the windows 0 to `Windows_g` - 1 only; the outputs of the others keep their reset values and are not used by the target |
| Irq | Registered OR of EVENTS AND IRQ_EN |

| Event flag | Sources |
| --- | --- |
| TGT_ERROR, TGT_CMD | Indication with a status other than 0, with status 0 |
| TGT_DISCARD | Header CRC error, incomplete header, reply received by the target |
| INI_REPLY | Reply confirmed without error |
| INI_ERROR | Reply discarded for a header error, unexpected reply, data error, rejected request |
| INI_TIMEOUT | Timeout of a command |
| ECC_SEC, ECC_DED | Events of the EDAC monitor |
| PKT_DISCARD | Packet without user port discarded, command received without target |

## 3. EDAC (MG-2)

`olo_ft_ecc_monitor` with 3 channels and 16-bit counters; `Rd_Ena` is always set, `Rd_Channel` is ECC_SELECT, a write
to ECC_COUNT is the read and clear of the selected channel, a write to ECC_STATUS the global clear.

| Channel | Buffer |
| --- | --- |
| 0 | Write buffer of the target (`olo_ft_fifo_sync`) |
| 1 | Write data of the AXI master (`olo_ft_axi_master_full`) |
| 2 | Read data of the AXI master (`olo_ft_axi_master_full`) |

A write to ECC_INJECT with SINGLE or DOUBLE set gives a one-cycle pulse on `Inj_Valid` of the channel with
`Inj_Double`; the target flips codeword bit 3 (single) or bits 3 and 5 (double) of the next word written to the
buffer. Channel 3 does not exist: its counters read zero and an injection into it is ignored.

## 4. Resources and timing

28 counters of 16 bits (448 flip-flops), 86 flip-flops per implemented window, about 120 flip-flops for the other
registers, and the read multiplexer. The window comparators are in the target; the MIB only holds the bounds.
