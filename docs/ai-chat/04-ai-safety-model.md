# AI Safety Model

- The model does not write SQL or raw database queries.
- The model does not mutate storage directly.
- The model may only choose registry-defined tools.
- Prompt injection in user text or stored text must not override system rules.
- Reports are service-calculated, not LLM-calculated.
- High-risk actions require confirmation.
- Confirmation executes stored arguments, not regenerated arguments.
- Success requires read-back verification.
