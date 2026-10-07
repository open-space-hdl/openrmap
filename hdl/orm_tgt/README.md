# orm_tgt

RMAP target (TG-1 to TG-5): decodes, checks and authorises commands, executes write, read and read-modify-write
commands on the target memory through an AXI4 master and sends the replies.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, configuration, interpretation of the standard |
| [Architecture](docs/architecture.md) | Blocks, state machines, write buffer and chunks |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results and findings |

Tests: `python run.py "*orm_tgt*"`
