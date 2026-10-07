# OpenRMAP: Code Coverage

## 1. Method

The code coverage of the OpenRMAP sources is measured with QuestaSim (Questa Pro Microchip Edition 2024.3) over the
complete regression of `run.py`, the same test set that GHDL runs in CI:

```shell
python run.py --questa --coverage -p 1
```

The sources of `hdl/<module>/src` are compiled with `+cover=sbcef`: statements, branches, conditions, expressions
(focused expression coverage) and state machines. Open Logic, UVVM and the testbenches are not instrumented; Open Logic
is verified by its own regression. `run.py` merges the coverage of all tests into `coverage/coverage.ucdb` and writes
the reports `coverage/coverage_report.txt` (details per instance) and `coverage/coverage_byfile.txt`; a design unit
is covered when any of its instances in any test covers it.

Closure rules:

- Statements, branches, state machine states and transitions: every item is covered by a test or listed with its
  justification in section 4. The transitions include the reset transitions from every state (architecture D12).
- Conditions and expressions: reported, not a closure criterion. Every miss was reviewed for untested behaviour
  (section 3); a term that cannot change the result was removed from the design.
- `-- coverage off` / `-- coverage on` are used for one kind of code only: the `when others` branch of a state machine
  whose enumerated state type lists every state. The branch is the recovery path of an illegal state (architecture
  D12) and cannot be reached in simulation.

## 2. Result

Run on 2026-10-07: 50 tests, all passed, 6 minutes with one simulator licence. Numbers are covered/total bins per
file; bold marks a metric with misses.

| File | Statements | Branches | FSM States | FSM Transitions | Conditions | Expressions |
| --- | --- | --- | --- | --- | --- | --- |
| `omap_core/src/omap_core.vhd` | **81/83** | **4/6** |  |  |  |  |
| `omap_core/src/omap_core_demux.vhd` | 74/74 | 54/54 | 5/5 | 8/8 | **15/16** |  |
| `omap_core/src/omap_core_mux.vhd` | 27/27 | 12/12 |  |  | 5/5 | 11/11 |
| `omap_initiator/src/omap_initiator.vhd` | 27/27 | 37/37 |  |  | 10/10 | **2/4** |
| `omap_initiator/src/omap_initiator_rx.vhd` | 108/108 | 69/69 |  |  | **28/29** | 7/7 |
| `omap_initiator/src/omap_initiator_tt.vhd` | 50/50 | 29/29 |  |  | **10/11** |  |
| `omap_initiator/src/omap_initiator_tx.vhd` | 106/106 | 66/66 | 10/10 | 19/19 | 4/4 | 2/2 |
| `omap_mib/src/omap_mib.vhd` | 185/185 | 95/95 |  |  | **18/19** |  |
| `omap_pkg/src/omap_pkg.vhd` | 13/13 | 6/6 |  |  | 2/2 |  |
| `omap_target/src/omap_target.vhd` | 18/18 | 2/2 |  |  |  |  |
| `omap_target/src/omap_target_auth.vhd` | 53/53 | 37/37 |  |  | 26/26 | 3/3 |
| `omap_target/src/omap_target_ctrl.vhd` | 268/268 | 164/164 | 16/16 | 43/43 | **65/74** | **7/10** |
| `omap_target/src/omap_target_mem.vhd` | 56/56 | 47/47 |  |  | **41/48** | **4/6** |
| `omap_target/src/omap_target_rx.vhd` | 89/89 | **66/67** |  |  | **14/15** | 6/6 |
| `omap_target/src/omap_target_tx.vhd` | 84/84 | 44/44 | 8/8 | 16/16 | 3/3 | 2/2 |
| Total | 1239/1241 (99.8 %) | 732/735 (99.6 %) | 39/39 (100.0 %) | 86/86 (100.0 %) | 241/262 (92.0 %) | 44/51 (86.3 %) |

## 3. Gaps found and closed

The first run (99.3 % of the statements, 98.0 % of the branches, 72.1 % of the state machine transitions) showed
behaviour that the requirements ask for but no test exercised, and the review of the condition misses found one
design defect and terms that cannot change a result.

| Gap | Resolution |
| --- | --- |
| Initiator: a command whose reply had been related to it stayed in the transaction table until the handshake of its confirmation; when the user held the confirmation, or the reply data took longer than the remaining timeout, the timer expired and the command was confirmed twice, with the reply and with a timeout | Design fix: the entry is removed in the cycle of the lookup (IN-TT-01). TC-IN-05 extended: confirmations held by the user, no timeout of the confirmed command; the test fails with the previous design |
| Reset in the middle of a command or request: 24 reset transitions of the state machines of the Target and the Initiator | New requirements TG-IF-06 and IN-IF-05, new tests TC-TG-16 (reset in each of the first 140 cycles of five commands, internal and external authorisation) and TC-IN-08 (reset in each of the first 80 cycles of three request situations) |
| Target: rejected command with an EEP immediately after the header; external rejection together with early EOP, excess data and Data CRC error, and without reply bit; reply requested while the encoder still sends the previous one; full write buffer; early EOP while committed chunks are still written; single errors in the write and read data of the AXI master | TC-TG-05, 09, 12, 14 and 15 extended |
| Initiator: held confirmations (reply, rejection, timeout); rejected read request; late data of a rejected request; read reply ending after the Header CRC | TC-IN-03, 04 and 05 extended |
| Register file: unused fourth word of a window | TC-MB-02 extended |
| Packet demultiplexer: non-RMAP packet of two characters at a node without user port | TC-CO-06 extended |
| Terms that cannot change a result: `Passthrough_g` in the event of a discarded packet; the ready signal inside the branch of the confirmation selection that is only reached when it is set; read-modify-write in the single-address checks (its command code has the increment bit set) and in the status of an externally rejected command (authorised in RmwExt_s); the command kind of an early EOP after an external rejection (only a write has data); a double error in a discarded word; the header status and the external rejection in the status of a completed write | Removed from the design |

The remaining condition and expression misses fall into three groups, none of them behaviour without a test:

- Terms masked by construction: the EDAC flags of a buffer are defined only together with its valid signal
  (`omap_target_ctrl.vhd` lines 706 and 707, `omap_target_mem.vhd` lines 259 and 260); a confirmation source keeps its
  valid signal until its handshake (`omap_initiator.vhd` lines 298 and 299); a lookup never relates a reply to an
  expired entry (`omap_initiator_tt.vhd` line 142); the channel of an injection command is never negative
  (`omap_mib.vhd` line 281); the end of the packet is presented only when no data byte is pending (`omap_target_rx.vhd`
  line 287).
- Gaps of an input stream in the cycle of a particular character: a gap before the end marker of a discarded packet
  (`omap_core_demux.vhd` line 269, `omap_initiator_rx.vhd` line 294). The handshakes themselves are covered with gaps
  and backpressure in the stress tests.
- Coincidences with the memory interface: the memory interface still busy, or a memory command still pending, when the
  last byte of a read, a read-modify-write or a write has been transferred (`omap_target_ctrl.vhd` lines 242, 431, 500,
  586, 617 and 682, `omap_target_mem.vhd` lines 174, 213, 222, 226 and 255). The AXI master is idle when the last byte
  has passed it in every test, also with 90 % backpressure of the memory; the conditions are the safe order of the
  completion and are kept.

## 4. Remaining misses

Two statements and three branches of the design remain uncovered. None of them is behaviour that a requirement asks
for:

| Location | Item not covered | Justification |
| --- | --- | --- |
| `omap_core/src/omap_core.vhd:189` to `191` | Statements and branches of the function `choose` | The function selects generics of the register file (number of windows and transactions of an absent Target or Initiator); QuestaSim evaluates it during elaboration, before coverage is collected. The results are checked through the GENERICS register in TC-CO-05 and TC-CO-06. |
| `omap_target/src/omap_target_rx.vhd:253` | Branch: end of the packet presented and not taken by the controller | Defensive handshake. The controller takes the end of the packet in every state that follows the handshake of the header (WrData, RdWait, RmwData, Drain), and the decoder presents the end only after that handshake. |

## 5. Reproduction

```shell
python run.py --questa --coverage -p 1
vcover report -byfile -details -zeros -code sbf coverage/coverage.ucdb
```

The second command lists the statements, branches and state machine items that are not covered, per file.
