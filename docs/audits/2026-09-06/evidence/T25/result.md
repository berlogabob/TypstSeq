# T25 Android profile result

Date: 2026-09-09
Status: COMPLETE — device profile measurement recorded.

The profile harness ran against the guarded `TyLogAuditVault` Android SAF fixture with the coordinator marker. It modeled the dashboard's unchanged 500 ms single-flight reload for exactly 60 seconds and restored the original `.tylog/sync_trace.jsonl` in teardown.

Recorded summary:

- Completed reloads: 121
- SAF `exists` probes: 121
- Full trace reads: 121
- Total trace bytes read: 3,191,980
- Load+parse: p50 46.516 ms, p95 56.548 ms, max 60.893 ms
- JSON parse: p50 1.194 ms, p95 2.118 ms, max 5.837 ms
- 16 ms ticker: 3,752 ticks, 0 dropped frames, worst gap 19 ms

The 121 SAF reads and 3,191,980 bytes occur only while the dashboard is open. With zero dropped frames and JSON parse p95 at 2.118 ms, the measurement does not justify a code fix or caching redesign.

The device run reported `01:00 +2: All tests passed!` and left the profile app running as requested.
