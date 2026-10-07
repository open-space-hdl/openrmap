# OpenRMAP Roadmap

The development follows the plan of the [architecture](architecture.md) (section 11). This page tracks the state of
every module; a module is done when its verification report is written and its regression is green.

## Modules

| Module | Blocks (architecture section 7) | Status |
| --- | --- | --- |
| `omap_pkg` | Common constants, RMAP CRC, register package | Done |
| `tb` (shared) | RMAP model, AXI memory model, AXI4-Stream and AXI4-Lite VVC wrappers | Done |
| `omap_target` | TG-1 to TG-5 (RMAP Target) | Done |
| `omap_initiator` | IN-1 to IN-3 (RMAP Initiator) | Done |
| `omap_mib` | MG-1, MG-2 (register file, EDAC monitor) | Done |
| `omap_core` | Core top level, CO-1, CO-2 | Done |

## Open items

| Item | State |
| --- | --- |
| Synthesis on a target device: resources and timing | Open; `tools/synth_vivado.py` runs the out-of-context flow with AMD Vivado, `lint/synth_check.py` checks the synthesizability of three node types with GHDL |
| Hardware test with a SpaceWire port and RMAP equipment | Open |
| Code coverage with QuestaSim | Done: [coverage.md](coverage.md) |
