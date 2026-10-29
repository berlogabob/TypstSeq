# 0001 - Attention and decisions

- Status: accepted
- Date: 2026-10-29

## Context

Six separate triage state lists existed (screenshot, idea, article, task, link suggestion, jobs), and new sources (OLT, Microsoft 365) would add more.

## Decision

One attention axis (new, kept, acted, archived) plus one append-only Decision log (seen, added-to-today, scheduled, accepted, rejected, dismissed, ignored). Old values map on read; there is no file migration. The old enrich folders are kept, because older builds read `enrich/feedback`.

## Consequences

- One Incoming view on Today.
- Thesis measures come from one log.
- Task and article progress stay separate from attention.
