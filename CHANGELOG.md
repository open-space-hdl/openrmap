# Changelog

The notable changes of OpenRMAP. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a
major version for an incompatible change of ports, stream formats, generics or register map, a minor version for a
feature and a patch version for a fix.

## [Unreleased]

### Changed

- Open Logic pinned to `4.7.0-ft.11` (was `4.7.0-ft.6` in release 0.1.0). Relevant to OpenRMAP: the memory master
  `olo_axi_master_full` takes the next chunk of a non-verified write while the bytes of the current one pass, so the
  chunks follow each other without a gap; section 9.2 of the user guide gives the new rate model of the writes and
  the limit of one read transaction every four cycles. The changes from
  `4.7.0-ft.10` to `4.7.0-ft.11` (`olo_base_crc`, the AMD constraint script of `olo_base_ram_sdp`) concern no unit
  that OpenRMAP uses.
- QuestaSim runs with a time resolution of 1 fs, as GHDL (`run.py`). Every time value of the testbenches is a whole
  number of nanoseconds, so the results of release 0.1.0 at 1 ps remain comparable.
- Verification: the test end compares the alert counters of every level itself and ends the simulation with a
  failure, whatever the stop limits of the test.

## [0.1.0] - 2026-10-18

First release. An RMAP Target and an RMAP Initiator according to ECSS-E-ST-50-52C. Verified by simulation (TRL 3)
in GHDL and QuestaSim, on Open Logic 4.7.0-ft.6.
