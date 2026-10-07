# omap_core

Top level of OpenRMAP (CO-1, CO-2): RMAP Target, RMAP Initiator and register file, the packet demultiplexer that
dispatches received packets to the Target, the Initiator or the user port, and the packet multiplexer that merges
replies, commands and user packets into the transmitted packet stream.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, configuration, interpretation of the standard, integration constraints |
| [Architecture](docs/architecture.md) | Demultiplexer, multiplexer, link stall with mutual Initiators |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results and findings |

Tests: `python run.py "*omap_core*"`
