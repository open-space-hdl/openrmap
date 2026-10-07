# OpenRMAP

OpenRMAP is an open Remote Memory Access Protocol (RMAP) implementation that is based on the Open Logic VHDL
Library. It implements an RMAP Target and an RMAP Initiator according to ECSS-E-ST-50-52C (SpaceWire: Remote memory
access protocol) and connects to the packet ports of a SpaceWire port such as the OpenWire core. The Target accesses
its memory through an AXI4 master; the Initiator takes requests and returns confirmations on AXI4-Stream style
interfaces; configuration, status and error information are in a register file behind an AXI4-Lite port. All
buffers use the fault-tolerant entities of [Open Logic](https://github.com/open-logic/open-logic) (SECDED ECC).

## Status

The core is complete and verified in simulation (GHDL and QuestaSim, 50 test cases at unit and core level, statement,
branch and state machine coverage closed, see [docs/coverage.md](docs/coverage.md)); the
[compliance matrix](docs/compliance.md) traces every ECSS clause in scope to its requirements and test cases. Two cores
access each other's memory through a packet network model, pass packets of other protocols, report injected network
faults with the status codes of the standard, and answer the commands of ECSS Annex A.4 with the replies of Annex A.4.
The [user guide](docs/user_guide.md) contains the conformance statement and the product characteristics of ECSS
clause 5.8. Synthesis results on a target device and a hardware test are open; see [docs/roadmap.md](docs/roadmap.md).

## Documentation

| Document | Content |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Architecture: building blocks, owned ECSS clauses, Open Logic usage, verification |
| [docs/user_guide.md](docs/user_guide.md) | Integration: sources, generics, interfaces, programming sequence, integration constraints, conformance statement and product characteristics |
| [docs/conventions.md](docs/conventions.md) | Coding, verification and repository conventions |
| [docs/roadmap.md](docs/roadmap.md) | Development plan and module status |
| [docs/compliance.md](docs/compliance.md) | ECSS compliance matrix: requirements and test cases of every clause (generated) |
| [docs/coverage.md](docs/coverage.md) | Code coverage of the regression with QuestaSim |
| [hdl/omap_mib/docs/register_map.md](hdl/omap_mib/docs/register_map.md) | Register map (generated; C header `sw/omap_regs.h`) |
| `hdl/<module>/docs/` | Specification, architecture, verification plan and verification report of each module |

## Repository structure

```text
openrmap/
|-- docs/             Top-level documentation
|-- hdl/<module>/     One folder per module: src/, tb/, docs/
|-- tb/               Verification components shared by the testbenches (RMAP model, AXI memory model)
|-- lint/             VSG configuration (Open Logic rules), synthesizability check
|-- tools/            Compliance matrix and register map generators, synthesis script for AMD Vivado
|-- sw/               C header of the register map (generated)
|-- open-logic/       Git submodule: Open Logic (fault-tolerant entities branch)
|-- uvvm/             Git submodule: UVVM verification framework
|-- component_list.txt  Modules in dependency order
`-- run.py            VUnit regression runner
```

## Running the tests

Prerequisites: Python 3, [GHDL](https://github.com/ghdl/ghdl) on the `PATH` and the Python packages of
`requirements.txt`.

```shell
git submodule update --init
python -m pip install -r requirements.txt
python run.py -p 8              # full regression with GHDL, 8 parallel simulations
python run.py "*omap_pkg*"      # one module
python run.py --questa <test>   # QuestaSim
```

`run.py` compiles Open Logic into the VHDL library `olo`, the required UVVM components into their own libraries and
all OpenRMAP sources into the library `openrmap`. `OMAP_GHDL_SIM_FLAGS` passes extra flags to the GHDL simulation,
for example `--vcd=wave.vcd` for a waveform.

Checks besides the regression:

```shell
python lint/lint.py                 # VSG, no errors and no warnings
python lint/synth_check.py          # synthesizability of three node types with GHDL
python tools/compliance.py --check  # every ECSS clause and requirement traced to a test case
python tools/regmap.py --check      # generated register map files match hdl/omap_mib/regs/omap_regs.yml
```

## Licence

OpenRMAP is licensed under the [PSI HDL Library License, Version 1.0](License.txt), the licence of Open Logic
(LGPL 2.1 with an exception for binaries, see [LGPL2_1.txt](LGPL2_1.txt)).
