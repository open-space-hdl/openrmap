# Changelog

The notable changes of OpenRMAP. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a
major version for an incompatible change of ports, stream formats, generics or register map, a minor version for a
feature and a patch version for a fix.

## [Unreleased]

### Changed

- Verification: the test end compares the alert counters of every level itself and ends the simulation with a
  failure, whatever the stop limits of the test.

## [0.1.0] - 2026-10-18

First release. An RMAP Target and an RMAP Initiator according to ECSS-E-ST-50-52C. Verified by simulation (TRL 3)
in GHDL and QuestaSim, on Open Logic 4.7.0-ft.6.
