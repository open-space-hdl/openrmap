# OpenRMAP Roadmap

The development follows the plan of the [architecture](architecture.md) (section 11). This page tracks the state of
every module; a module is done when its verification report is written and its regression is green.

## Modules

| Module | Blocks (architecture section 7) | Status |
| --- | --- | --- |
| `orm_pkg` | Common constants, RMAP CRC, register package | Done |
| `tb` (shared) | RMAP model, AXI memory model, AXI4-Stream and AXI4-Lite VVC wrappers | Done |
| `orm_tgt` | TG-1 to TG-5 (RMAP target) | Open |
| `orm_ini` | IN-1 to IN-3 (RMAP initiator) | Open |
| `orm_mib` | MG-1, MG-2 (register file, EDAC monitor) | Open |
| `orm_core` | Core top level, CO-1, CO-2 | Open |
