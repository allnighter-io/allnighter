# thread — layout-watcher verdict (CR4b chat reply)

Fixtures: thread-chat · thread-with-turns
Command: `bash scripts/gui_proof.sh <fixture>`

CR4b: Chat send routes the message to the chosen model via WorkerChatCoordinator
and renders its reply as a `workerChat` turn — brand glyph + model name +
timestamp + markdown body, with running/failed/cancelled states. (Fan out /
Execute still record the user turn only; CR4c/d.)

## VERDICT: PASS

Disinterested layout-watcher on the current render (app window; ignoring desktop +
menu bar).

thread-chat: P1 none · P2 left-rail search shows stray placeholder text, minor;
chips slightly low-contrast but legible. All expected elements — rail row, header,
"You" bubble, Opus 4.8 reply (glyph/name/timestamp/multi-line markdown), docked
composer — visible and aligned, no clipping/overlap/z-order break.

One-line summary: A model's reply renders correctly in the thread; PASS.
