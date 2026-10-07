# omap_initiator

RMAP Initiator (IN-1 to IN-3): builds commands from request descriptors and a data stream, decodes the replies and
returns confirmations and the data read; an optional transaction table associates replies with the outstanding
commands and reports timeouts.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, configuration, interpretation of the standard |
| [Architecture](docs/architecture.md) | Encoder, decoder, transaction table, confirmation selection |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results and findings |

Tests: `python run.py "*omap_initiator*"`
