# Bot vaults: proposed TyLog boundary

**Status:** design proposal for user decision. No architecture choice in this document is approved, and implementation remains frozen.

**Inputs:** `Amadora-News-Bot/docs/2026-10-31-architecture-tylog-brain.md`, `Amadora-News-Bot/PLAN.md`, and the read-only `LuzDoBot-repo` checkout. The latter is a project index linking to a wiki, the LuzDoBot application, and a report generator; its local checkout contains a sentiment dataset and analysis script, but no implementation or storage contract to reuse.

## Proposed direction

Keep collection, Telegram delivery, channel schedules, drafts, and the publication queue in each bot. Put reusable knowledge processing and durable evidence in TyLog-managed bot spaces. Treat a channel as a profile inside a bot space, so channels can share knowledge while retaining separate eligibility rules and review modes. Start with Amadora as the first adapter; do not migrate Decent Sampler, IoT_News, or LuzDoBot until the boundary and baseline are accepted.

The bot-to-TyLog boundary should be a versioned, append-oriented handoff: the bot submits a normalized item plus source and channel context; TyLog returns a stable item key, duplicate/follow-up assessment, entity and source references, and a readiness result; the bot owns the resulting draft and Telegram interaction. Decisions return to TyLog as append-only events. Retries use stable IDs so resubmission cannot create a second decision or item. If TyLog is unavailable, collection may continue into a durable bot-owned queue, but the bot must not publish an item without a recorded readiness result. These are proposals, not existing capabilities.

Preserve enough evidence to compare decisions over time: normalized source URL, original title and text, generated draft, decision and timestamps, channel, and versions of the profile, rules, and prompt. Keep raw candidate traffic in a bounded bot-side journal or cache; create ordinary TyLog notes only for items a person keeps, acts on, or publishes, plus durable entities and sources. Do not place high-volume transient candidates in the normal note index by default.

## Five questions for decision

1. **Should bot knowledge appear beside personal notes?** **Proposal:** separate bot vaults or explicitly selected bot spaces, hidden from ordinary personal-note views by default. Let the user open a bot space in TyLog when reviewing its graph and reports. This limits accidental mixing and keeps high-volume bot material out of personal search; shared knowledge can be exported as a reviewed `ModulePack` where appropriate. Decide whether the first release needs a separate vault or whether a space boundary in one vault is sufficient.

2. **Should the research baseline start now?** **Proposal:** begin a daily, access-restricted copy of Amadora's `state.json` before any code changes, with a retention period and integrity hashes. It is the smallest way to preserve existing decisions, but it does not capture raw items or rule versions and therefore is not a complete baseline. Before changing bot code, add versioned capture of source text, draft text, and the profile/rule/prompt versions. Decide whether to start the state copy now and what retention/privacy policy applies.

3. **How should topic and project spaces work?** **Proposal:** one TyLog store can contain isolated bot spaces, with channel profiles scoped to a space and explicit cross-space sharing. This supports one bot serving multiple channels and reusable sources or terms without forcing every channel into one graph. Keep space IDs stable and include them in every handoff and decision. Decide whether space isolation inside one store is acceptable or whether each bot/topic requires a separate store.

4. **Where should the processing brain run?** **Proposal:** run the first brain as a server-side TyLog Core service beside the bot, using durable inbox/outbox files or an equivalent local queue. Keep the phone app as the review and analysis client. Do not move semantic search into Core until its model/runtime and measured server requirements are clear; the current semantic search is in Flutter, while Core already has indexing and `EnrichMemory`. A Python service over the format is a fallback only if Core cannot meet the deployment needs, because it would duplicate domain behavior. Decide whether Core may be extended with server-capable retrieval or whether a separate Python brain is preferred.

5. **Who writes the draft?** **Proposal:** TyLog should return assessments and structured facts, while the bot writes the channel-specific draft using its profile and retains ownership of edits, buttons, scheduling, and publication. Record the generator and prompt version with each draft. This keeps Telegram behavior and channel voice with the bot while allowing TyLog to improve duplicate checks, entity matching, and source evaluation. Decide whether TyLog should generate the prose too, or only provide the knowledge assessment.

## Deferred scope question

The source architecture note has a sixth open question: whether IoT_News joins this system. M6 specifies five questions, so this remains deferred. **Proposal:** keep IoT_News outside the first implementation until the Amadora boundary works and its `news_memory.py` behavior has been mapped to the shared item and decision model. Revisit it before claiming a common multi-bot architecture.

## Delivery sequence after decisions

1. Approve the vault/space boundary, baseline and retention policy, runtime, and draft ownership.
2. Specify the handoff schema, idempotency, failure behavior, and versioned evidence fields.
3. Build one Amadora vertical slice: submit one item, receive an assessment, create/review a Telegram draft, and append its decision; verify retries and service outage recovery on scratch data.
4. Measure baseline coverage and decision metrics before migrating another bot or expanding to more channels.

No code, data migration, bot deployment, or vault write is included in M6.

## TyLog read-only mount slice (schema 1)

On desktop, Extensions → Add bot vault selects a folder containing `bot-vault.json` with `{"schema": 1}`. TyLog mounts it read-only using the existing folder mount and lists indexed Typst notes when the mount is opened; an item opens as read-only source. A higher schema is rejected with “needs newer TyLog”. The manifest is checked again when opening the mount. Existing folder indexing makes these notes visible in ordinary search; isolation is tracked in P6a-rest. This minimal manifest does not define a draft or decision protocol, and does not claim interoperability with a bot producer.
