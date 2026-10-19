# Editor checks (WORLD-TECH-01)

Isolated copy of the 2 km world (`worlds/edit_test_2km`, git-ignored), editor on Vulkan,
driven through the Godot AI MCP by setting `EditorProbe.run = true` (`tools/editor_probe.gd`).

| Run | Result |
|---|---|
| 1 | Sculpt via Terrain3DEditor: +0.01 m only (stroke too weak); undo/redo exact. Road move: no terrain change — the Road Generator connector skips the first road update after a scene load (`_skip_scene_load`). Save OK. |
| 1b | After `scene_open(force_reload=true)` through MCP, the next probe run crashed the editor (signal 11, official build without symbols). Likely stale scene/terrain reference in the editor plugin after a programmatic reload; **cause not confirmed**. See `editor_run1_crash.log`. |
| 2 (fresh editor) | Sculpt +2.17 m, undo restores 41.636 m exactly, redo restores 43.805 m exactly. Road move x2: connector flattens terrain (41.44 -> 43.03 m at probe point); undo x2 restores RoadPoint and terrain exactly. Save OK. Clean editor exit (code 0). |
| Reopen | New process loads saved scene: sculpt height 43.805 m persisted, RoadPoint and terrain under it at undone state. |
