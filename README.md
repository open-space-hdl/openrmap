# OpenRMAP

OpenRMAP is an open Remote Memory Access Protocol (RMAP) implementation that is based on the Open Logic VHDL
Library. It implements an RMAP target and an RMAP initiator according to ECSS-E-ST-50-52C (SpaceWire: Remote memory
access protocol) and connects to the packet ports of a SpaceWire port such as the OpenWire core. The target accesses
its memory through an AXI4 master; the initiator takes requests and returns confirmations on AXI4-Stream style
interfaces; configuration, status and error information are in a register file behind an AXI4-Lite port. All
buffers use the fault-tolerant entities of [Open Logic](https://github.com/open-logic/open-logic) (SECDED ECC).

## Status

Under development; see [docs/roadmap.md](docs/roadmap.md).

## Documentation

| Document | Content |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Architecture: building blocks, owned ECSS clauses, Open Logic usage, verification |
| [docs/conventions.md](docs/conventions.md) | Coding, verification and repository conventions |
| [docs/roadmap.md](docs/roadmap.md) | Development plan and module status |
| `hdl/<module>/docs/` | Specification, architecture, verification plan and verification report of each module |

## Repository structure

```text
OpenRMAP/
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
python run.py "*orm_pkg*"       # one module
python run.py --questa <test>   # QuestaSim
```

`run.py` compiles Open Logic into the VHDL library `olo`, the required UVVM components into their own libraries and
all OpenRMAP sources into the library `openrmap`. `ORM_GHDL_SIM_FLAGS` passes extra flags to the GHDL simulation,
for example `--vcd=wave.vcd` for a waveform.

Checks besides the regression:

```shell
python lint/lint.py                 # VSG, no errors and no warnings
python tools/compliance.py --check  # every ECSS clause and requirement traced to a test case
python tools/regmap.py --check      # generated register map files match hdl/orm_mib/regs/orm_regs.yml
```

## Licence

OpenRMAP is licensed under the [PSI HDL Library License, Version 1.0](License.txt), the licence of Open Logic
(LGPL 2.1 with an exception for binaries, see [LGPL2_1.txt](LGPL2_1.txt)).
