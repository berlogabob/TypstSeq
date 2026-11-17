# 0003 - Lab equipment identity and typed loan lines

- Status: accepted
- Date: 2026-11-17

## Context

Lab equipment reached TyLog in two ways:

- `openlabtwin/scripts/export_tylog.py` writes `equipment` and `place` notes into `labs/inventory/`. The note id is the asset tag. The resolver and loan tasks (Wave 34) link to these notes.
- `OltConnector` builds `olt:place:*` and `olt:asset:*` entities on each device after an OLT sign-in.

One shelf or console could therefore appear twice, and only the first path worked offline or without a sign-in. Loans could be entered only as natural language that went through the LLM.

## Decision

1. **One identity.** Equipment is identified by its asset tag and places by their place code, and both reach TyLog only through the vault export (`source: openlabtwin`). The export overwrites these notes, and TyLog never edits them; changes are made in OLT. `OltConnector` keeps only bookings and ideas (Incoming).
2. **OLT holds the loan record.** A loan task in TyLog is an input. `tool/lab_bridge.py` turns it into OLT `issue` and `return` movements whose note is `tylog:<task-id>:<tag>:out|return`. OLT's answer (recorded, or refused with a reason) comes back as a log in `_system/lab/results/` and is never written into a `.typ` file.
3. **Typed loan lines.** `/loan out <equipment> to <person> [due <date>]` and `/loan return <equipment>` are parsed without an LLM. They lead to the same review card as an LLM proposal, and that card shows the typed command it would run.

## Consequences

- One node per item in the graph and the tree, available offline on every device.
- The thesis can compare channels (office, TyLog sentence, typed line) inside one movement log.
- A typed line is a baseline against the LLM path. It has the same validation and the same decision log, and no model involved.
- The connector's live stock view is gone. Where something is comes from the latest export.
