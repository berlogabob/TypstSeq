/// Status of a fact (link, mention, tag) or vocabulary item (tag, entity
/// kind, cluster). See docs/adr/0002-knowledge-states.md.
enum KnowledgeStatus { proposed, accepted, rejected, auto, obsolete }

/// Parses a stored status name; unknown or null -> null.
KnowledgeStatus? parseKnowledgeStatus(String? name) =>
    KnowledgeStatus.values.where((s) => s.name == name).firstOrNull;

/// True when the item is part of the user's knowledge (drawn solid).
bool isKnown(KnowledgeStatus status) =>
    status == KnowledgeStatus.accepted || status == KnowledgeStatus.auto;
