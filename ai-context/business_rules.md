# Business Rules

- All AI actions must come from the registry.
- Tool schemas are strict objects with no extra properties.
- Missing required fields must lead to clarification, not guessing.
- Multiple matches must lead to disambiguation.
- Write / delete / export / financial operations must be confirmed.
- Confirmation must execute stored normalized arguments.
- Reports must be calculated by app services, not by the LLM.
- Success text must not claim completion without read-back verification.
- Tenant/account scope must be respected for all reads and writes.
