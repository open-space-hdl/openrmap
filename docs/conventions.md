# OpenRMAP Conventions

OpenRMAP follows the coding conventions of Open Logic and the module development process of the architecture
document. This page lists the rules and the few OpenRMAP-specific additions.

## VHDL coding

- The [Open Logic coding conventions](../open-logic/doc/Conventions.md) apply in full: port names
  `<Interface>_<Signal>`, generics `_g`, constants `_c`, variables `_v`, types `_t`, FSM types `<Name>Fsm_t` with
  states `_s`, functions in `lowerCamelCase`, four spaces of indentation, no tabs, no trailing whitespace.
- Entities are named `omap_<function>` (for example `omap_target_rx`). All OpenRMAP sources are compiled into the VHDL
  library `openrmap`; Open Logic is compiled into the library `olo`.
- Language: VHDL-2008.
- Entities with non-trivial state use the two-process pattern of Open Logic: all registers in one `TwoProcess_r`
  record, signals `r` and `r_next`, a combinational process starting with `v := r;` and ending with
  `r_next <= v;`, a sequential process with `r <= r_next;` and the reset override at its end.
- Resets are synchronous and high-active. Only state registers are reset. The core has one clock domain `Clk`.
- Every data path between blocks is a valid / ready stream (AXI4-Stream handshake semantics) or a valid-only stream
  of one-cycle events where the receiver is never slower than the source.
- Standard functions (FIFOs, RAMs, crossings, synchronisers, arbiters, pipeline stages) are instantiated from Open
  Logic, never rewritten. FIFOs and crossings use the fault-tolerant `olo_ft_*` entities.
- State machines have a `when others` branch that returns to a defined recovery state; the reset leads to that state
  from any state.
- Every line that implements an ECSS requirement is traceable through the module specification; comments name the
  clause where it helps the reader (for example `-- ECSS 5.3.3.6.3a`).
- File header: copyright line and authors, then a 1 to 2 sentence description that links to the module
  documentation. Never write "all rights reserved".
- Never use em-dashes in code, comments or documentation. Use UTF-8 only.
- VSG 3.27 with the Open Logic configuration in `lint/config` must report no errors and no warnings:
  `vsg -c lint/config/vsg_config.yml -f <file>`. Safe automatic fixes:
  `vsg -c lint/config/vsg_config.yml --fix --fix_only lint/config/fix_only_config.yml -f <file>`.
- The design must be synthesizable in a technology-independent way: `python lint/synth_check.py` elaborates
  `omap_core` with the synthesis of GHDL (after `python run.py --compile`) and fails on errors and inferred latches.
  `to_01` and other simulation-only functions are not used in RTL.
- Traceability: every requirement of a specification is verified by at least one test case of the verification plan,
  every ECSS clause of the traceability matrix (architecture section 10) by the test cases of its requirements, and
  every test case of a plan is run by a testbench. `python tools/compliance.py` writes the
  [compliance matrix](compliance.md); `python tools/compliance.py --check` fails on a gap.

## Module development process

Every module goes through the seven phases of the architecture document (section 9):

| Phase | Output |
| --- | --- |
| A Requirements | `hdl/<module>/docs/specification.md`: requirements with IDs, each tracing to ECSS clauses |
| B Architecture | `hdl/<module>/docs/architecture.md`: blocks, ports, state machines, data formats |
| C Verification plan | `hdl/<module>/docs/verification_plan.md`: test cases with IDs, requirement coverage |
| D RTL | `hdl/<module>/src/*.vhd` |
| E Testbenches | `hdl/<module>/tb/<entity>_th.vhd` (harness) and `<entity>_tb.vhd` (VUnit runner) |
| F Verification | Regression green, `hdl/<module>/docs/verification_report.md` |
| G Integration | Tests at the next level that cross every seam the module touches |

A module is one layer or one group of blocks of the architecture (section 7). Every block keeps its own entity and
its own unit testbench. `hdl/<module>/README.md` links the four documents and explains how to run the tests.

## Verification

- VUnit runs every test (`run.py`); UVVM supplies VVCs, BFMs, checks, randomisation and functional coverage.
- The harness (`_th`) contains clocks, reset, the DUT and the VVCs, the testbench (`_tb`) contains one
  `if run("<test id>") then` block per test case of the verification plan. The test IDs of the plan and the names
  in `run(...)` are identical.
- A test passes only when UVVM reports no unexpected alerts and every expected alert occurred
  (`omap_tb_pkg.omapTestEnd`).
- Tests observe ports and management interfaces only, never internal signals.
- GHDL is the default simulator; QuestaSim (`python run.py --questa`) is used for code coverage
  ([coverage.md](coverage.md)). Every test passes in both simulators.
- A side effect is never obtained by calling an impure function and discarding its result: QuestaSim may remove such
  a call. Protected types offer a procedure for it.
- Packets are built and checked by the RMAP model of `tb/` (own implementation of the packet formats and of the
  CRC with the table method of ECSS Annex A.3); tests never use the RTL of the core to build or check packets.
- Target memory is the AXI memory model of `tb/`; written data is checked through its backdoor.
- Negative tests inject the fault from the bench (corrupted CRC, early EOP, EEP, excess data, wrong key, error
  response of the memory, double error through the `ErrInj` ports, ...) and expect the status in the reply, the
  confirmation or the counters of the register file.

## Git

- `main` holds the integrated state. Every module or change is developed on a branch `feature/<module>` or
  `bugfix/<topic>` and merged with `--no-ff` once its regression is green.
- Commit messages: imperative subject line, body explains what and why.
