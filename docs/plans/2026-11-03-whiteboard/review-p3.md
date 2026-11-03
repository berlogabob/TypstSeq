
1. **Data loss — [whiteboard.dart:249](/Users/berloga/Documents/GitHub/TypstSeq/lib/widgets/whiteboard.dart:249):** Closing the editor queues a pending save but does not wait for it. Reopening the board before that write finishes can load stale content, and the new editor can overwrite the previous edits. Flush and await writes before leaving, using a shared per-board write queue.

2. **Data loss during sync — [whiteboard.dart:233](/Users/berloga/Documents/GitHub/TypstSeq/lib/widgets/whiteboard.dart:233):** A save writes the editor’s entire in-memory snapshot without checking whether sync has replaced the file since it was opened. A subsequent pan or edit can overwrite another device’s downloaded changes without producing a conflict. Track the loaded file revision or hash and reload, merge, or surface a conflict before saving over a changed file.

3. **Performance — [whiteboard.dart:620](/Users/berloga/Documents/GitHub/TypstSeq/lib/widgets/whiteboard.dart:620):** Every drag or viewport update rebuilds visible cards and creates new image-read futures; note cards likewise reread their files at line 657. Cache the futures or content by reference, invalidate them when content changes, and isolate card content from canvas movement.

4. **Performance — [whiteboard.dart:628](/Users/berloga/Documents/GitHub/TypstSeq/lib/widgets/whiteboard.dart:628):** Image thumbnails decode at the original image resolution. Several phone photos can consume substantial memory despite being displayed in small cards. Decode at the rendered thumbnail size using the device pixel ratio.

5. **Performance — [whiteboard.dart:838](/Users/berloga/Documents/GitHub/TypstSeq/lib/widgets/whiteboard.dart:838):** Every rebuild creates hit targets for all edges and scans the card list twice per edge; the painter repeats those scans. A large connected board therefore does quadratic work during pan and drag. Index cards by ID and cull edge targets and painting to the viewport.

6. **Frame correctness — [board.dart:373](/Users/berloga/Documents/GitHub/TypstSeq/packages/tylog_core/lib/src/board.dart:373):** Frame membership is recalculated on every drag update. A stationary card swept over by the moving frame can become a member and be carried away. Capture the contained card IDs at drag start and move only those cards until the gesture ends.

7. **Existing boards open incorrectly — [whiteboard.dart:94](/Users/berloga/Documents/GitHub/TypstSeq/lib/widgets/whiteboard.dart:94):** The Boards list includes column-layout boards, but opening any entry constructs a whiteboard canvas. Existing kanban boards consequently appear empty and can be edited through the wrong layout. Dispatch by `board.layout`, or restrict this list to whiteboards and provide the correct kanban route.

8. **Card selection — [whiteboard.dart:858](/Users/berloga/Documents/GitHub/TypstSeq/lib/widgets/whiteboard.dart:858):** Tapping a card selects it and immediately opens its note, task, URL, or text editor. Users cannot simply select such a card and then delete it. Separate selection from opening, for example with an explicit Open action.

9. **Paste — [whiteboard.dart:390](/Users/berloga/Documents/GitHub/TypstSeq/lib/widgets/whiteboard.dart:390):** Paste reads only plain text, so image clipboard data is ignored. Paste is also reachable only through a keyboard shortcut, leaving mobile users without the specified paste action. Add an accessible paste control and route clipboard image bytes through the asset-copy path.

10. **Accessibility — [whiteboard.dart:855](/Users/berloga/Documents/GitHub/TypstSeq/lib/widgets/whiteboard.dart:855):** Card selection, movement, connection, and resize depend on gestures without corresponding labeled semantic or keyboard actions. Provide focusable controls and semantic actions for these operations.
