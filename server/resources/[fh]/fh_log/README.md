# fh_log

Minimal `rsg-log` provider (`provide 'rsg-log'` in `fxmanifest.lua`) so audit events from `rsg-core`, `rsg-chat`, and `fh_inventory` are captured instead of dropped.

## What it does
- Listens on server-internal `rsg-log:server:CreateLog(channel, title, color, msg, tagEveryone?)` (`AddEventHandler` only; not exposed as a client net event).
- Formats each entry onto a single sanitized line (newlines and control characters stripped; tolerates `nil` or non-string arguments).
- Prints `[fh_log] <line>` to the server console and appends `<line>` to `server/logs/audit.log` (creating `server/logs/` if missing).
- File writes are buffered: one append per flush, every ~2 s, at 500 buffered lines, and on fh_log's `onResourceStop` (a hard crash can lose the last ~2 s of file lines; the console lines are immediate).
- `audit.log` is size-capped: a flush that would take it past the cap first renames it to `audit.log.1` (an older `.1` is overwritten), so the two files hold at most about twice the cap. Cap in KB from the convar `fh_log_max_kb` (default `5120` = 5 MB; e.g. `set fh_log_max_kb 10240` in server.cfg).

## Load order
Ensured in `server/server.cfg` right after `oxmysql` / `ox_lib` and before `rsg-core`, `fh_inventory`, and `rsg-chat`.

## Tests
Formatter, buffering and rotation spec: `spec/fh_log_spec.lua`.
