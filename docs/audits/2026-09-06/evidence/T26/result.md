# T26 device profile result

The Android profile harness passed on the guarded `TyLogAuditVault` device vault. It recorded 30 idle and 30 contended read-plus-atomic-save samples, and all final bytes, hashes, and decoded content passed integrity checks.

| Condition | p50 | p95 | max |
| --- | ---: | ---: | ---: |
| Idle | 263.005 ms | 324.590 ms | 325.020 ms |
| Attachment contention | 263.845 ms | 545.309 ms | 744.101 ms |

The contention run transferred 24 MiB in 9,114 ms, with the transfer active during 30/30 contended samples. Relative to idle, contention increased p95 latency by 68% and maximum latency by 129%; the tail cost is material even though p50 was nearly unchanged.

Avoid scheduling bulk attachment writes alongside interactive saves. Keep the existing atomic-write and locking behavior unchanged; no correctness or UI failure was reproduced that would justify changing it.

The result is valid only for the Android profile build and the harness guard requiring the active `android-tree` registry entry named exactly `TyLogAuditVault`, a persisted SAF grant, and the `README-AUDIT.txt` coordinator marker.
