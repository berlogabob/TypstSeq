# P09d1 result — application database lifecycle

Accepted 2026-09-15.

`HomeScreen` owns one asynchronous database instance for its full state lifetime, exposes the future to its import flow parts, and closes the resolved instance on disposal. Production uses `openDatabase()`; Flutter tests avoid the production database by default. Narrow opener, closer, and startup callbacks allow lifecycle tests without platform vault initialization.

Validation: the widget lifecycle test proves a same-key rebuild opens once and disposal closes once. Targeted analysis reports no issues.
