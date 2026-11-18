# Changelog

The notable changes of OpenRMAP. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a
major version for an incompatible change of ports, stream formats, generics or register map, a minor version for a
feature and a patch version for a fix.

## [Unreleased]

## [0.1.2] - 2026-11-18

Maintenance release on Open Logic 4.8.0-ft.2 (1f4a6c3), based on Open Logic 4.8.0. Ports, generics, stream formats
and the register map are unchanged. Verified by simulation (TRL 3) in GHDL and QuestaSim.

### Changed

- Open Logic pinned to `4.8.0-ft.2` (1f4a6c3), based on Open Logic 4.8.0 (was `4.7.0-ft.11` in release 0.1.1). Of
  the 22 Open Logic files that OpenRMAP uses, only `olo_axi_master_full.vhd` changes: it counts the bytes of a
  command in two bits fewer than the address also at 8-bit AXI data (4.7.0-ft.11: one fewer) and stops the
  elaboration otherwise.
- Memory master of the Target: the size width of a command is two bits fewer than the address at every data width
  (`memSizeBits`, at most 24). At `AxiDataWidth_g` 8 with `AxiAddrWidth_g` 12 to 25 the largest command halves to
  2^(`AxiAddrWidth_g` - 2) - 1 bytes (1023 at 12 bits), and longer accesses are split into more commands, as at the
  other data widths. With the size width of 0.1.1 these configurations fail elaboration on the new pin. Every other
  configuration gives the memory master the same generics as before; no generic value becomes invalid.
- Documentation: the README and the roadmap name the hardware test as part of a reference system of the family as
  the path to TRL 4.

### Fixed

- Documentation website: builds with Python-Markdown 3.11.3 (heading anchors hook takes the new optional argument;
  markdown pinned).

### Verification

- GHDL 6.0.0 (mcode): the full regression, 107 of 107 tests passed, 0 skipped (CI run 44305180867 on the release
  head bcbb24d); `lint/synth_check.py` 151 configurations, 0 failed. On the repin alone (3d62814) the regression had
  failed one test of 107, TC-TG-20 in the configuration `addr12_axi8`, at the elaboration check of
  `olo_axi_master_full` (CI run 44303786161); the change of the size width corrects it.
- QuestaSim 2024.3 (time resolution 1 fs) on bcbb24d, with code coverage because the RTL changed since release 0.1.1
  (`omap_pkg`): 107 of 107 passed, 0 skipped. This run is also the functional evidence of QuestaSim; there is no run
  without code coverage. Code coverage ([docs/coverage.md](docs/coverage.md)): statements 1237/1243, branches
  727/734, state machine states 39/39 and transitions 86/86, every miss justified; conditions 224/240 and expressions
  46/55 (reported). Against release 0.1.1 only `omap_pkg` changes: the removed 8-bit branch of `memSizeBits` takes one
  covered statement and two covered branch bins away; the misses are the same items.
- xsim: not needed, OpenRMAP has no vendor-specific parts. Synthesis: `lint/synth_check.py` above; no device
  synthesis of an earlier release to compare with (roadmap).
- The evidence of bcbb24d holds for the release head: the later commits change only the records in `docs` and
  `hdl/*/docs`, outside the evidence paths.

## [0.1.1] - 2026-10-25

Maintenance release on Open Logic 4.7.0-ft.11. The sources of the core are unchanged from 0.1.0; ports, generics,
stream formats and the register map are unchanged. Verified by simulation (TRL 3) in GHDL and QuestaSim.

### Changed

- Open Logic pinned to `4.7.0-ft.11` (was `4.7.0-ft.6` in release 0.1.0). Relevant to OpenRMAP: the memory master
  `olo_axi_master_full` takes the next chunk of a non-verified write while the bytes of the current one pass, so the
  chunks follow each other without a gap; section 9.2 of the user guide gives the new rate model of the writes and
  the limit of one read transaction every four cycles. The changes from `4.7.0-ft.10` to `4.7.0-ft.11`
  (`olo_base_crc`, the AMD constraint script of `olo_base_ram_sdp`) concern no unit that OpenRMAP uses.
- QuestaSim runs with a time resolution of 1 fs, as GHDL (`run.py`). Every time value of the testbenches is a whole
  number of nanoseconds, so the results of release 0.1.0 at 1 ps remain comparable.
- Verification: the test end compares the alert counters of every level itself and ends the simulation with a
  failure, whatever the stop limits of the test.
- Verification: `python tools/compliance.py --check` also fails when `docs/compliance.md` is out of date (the matrix
  is generated in memory and compared with the file), and the CI shows with a step that a stale matrix fails it. The
  generated matrix is reproducible: test case entries of the same group and number are ordered by their full text,
  not by the iteration order of a set, which changes with the hash seed of every Python process.

### Fixed

- Documentation site: `selectolax` is pinned to 1.0.0 (`tools/docs/requirements.txt`); with 1.0.1 the site was built
  without its diagrams.

### Verification

- GHDL 6.0.0 (mcode): the full regression, 107 of 107 tests passed, 0 skipped (CI run 40180860931 on the release
  head b7664c8, CI run 40180419212 on the Open Logic pin); `lint/synth_check.py` 151 configurations, 0 failed.
- QuestaSim 2024.3 (time resolution 1 fs) on b7664c8: 107 of 107 with code coverage and 107 of 107 without, 0
  skipped. Code coverage ([docs/coverage.md](docs/coverage.md)): statements 1238/1244, branches 729/736, state
  machine states 39/39 and transitions 86/86, every miss justified; conditions 224/240 and expressions 46/55
  (reported). The same figures and misses as release 0.1.0.

## [0.1.0] - 2026-10-18

First release. An RMAP Target and an RMAP Initiator according to ECSS-E-ST-50-52C. Verified by simulation (TRL 3)
in GHDL and QuestaSim, on Open Logic 4.7.0-ft.6.
