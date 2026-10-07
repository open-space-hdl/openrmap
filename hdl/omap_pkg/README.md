# omap_pkg

Definitions shared by all OpenRMAP modules: RMAP field values, command and status codes, the RMAP CRC, the decoded
command header and the address windows of the Target. The module also verifies the shared verification components
in `tb/` (RMAP model, AXI memory model).

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements |
| [Architecture](docs/architecture.md) | Contents, CRC, command codes, verification components |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results |

Tests: `python run.py "*omap_pkg*"`
