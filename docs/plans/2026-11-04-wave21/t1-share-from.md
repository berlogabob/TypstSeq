# T1: "From" person on shared audio

Problem: audio shared from WhatsApp/Telegram (e.g. `PTT-20261104-WA0001.opus`) carries no sender; the note is not linked to the person.

Do:
- After a shared audio (or any shared file that creates a note via lib/app_mobile/audio_flow.dart `_saveSharedAudio`, and the WhatsApp/Telegram share path that produced `notes/Audio PTT-…typ`, find it) is saved, show a small non-blocking bar/sheet "From whom?" with: the last 5 people chosen for shares (most recent first), a search field over entity pages (kind person, or kind note pages that look like people are fine to include; reuse the existing note search/picker if one exists), and Skip.
- Choosing a person writes `From: #tylog.ref-note("<id>")[<title>]` into the note body next to the existing `From:` daily line (keep the daily link; add the person link on the same line or the next line), via the existing surgical write helpers (workspace.mutateNote). Never rewrite the whole note.
- Remember recent choices per device in app-local storage (not the vault). No sender guessing.
- Skip = nothing written.
Tests: widget/unit test that choosing a person adds exactly one ref-note link and Skip writes nothing; output must compile (see existing compile helpers in tests).
