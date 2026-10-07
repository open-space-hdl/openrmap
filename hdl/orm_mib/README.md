# orm_mib

Management block (MG-1, MG-2): register file with the configuration of the target and the initiator, the product
characteristics, the error information, event flags and interrupt behind an AXI4-Lite slave, and the EDAC monitor of
the FT buffers with error injection.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, configuration, interpretation of the standard |
| [Architecture](docs/architecture.md) | Register file, event flags, EDAC channels |
| [Register map](docs/register_map.md) | Registers and fields (generated from `regs/orm_regs.yml`) |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results and findings |

Tests: `python run.py "*orm_mib*"`
