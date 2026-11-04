# T2: stabilize two flaky tests

Under full-suite load these fail intermittently:
- test/workspace_controller_test.dart "scanned issues survive index publication and later refreshes"
- test/whiteboard_test.dart "entity Tree opens and pins nodes and edges without duplicate cards"
Find the race (likely real IO inside fake async, or a completer/timer not awaited). Repo test rules: real IO inside `tester.runAsync`, pump outside it, never `pumpAndSettle` on spinners, poll files rather than completers. Fix the test or the product race (if the product has a real race, fix the product). Prove: run each file 10x in a loop plus the whole suite once under load (`flutter test -j 8`), all green.
