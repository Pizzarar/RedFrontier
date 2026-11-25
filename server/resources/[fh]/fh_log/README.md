# fh_log

Minimal `rsg-log` provider (`provide 'rsg-log'` in `fxmanifest.lua`) so audit events from `rsg-core`, `rsg-chat`, and `fh_inventory` are captured instead of dropped.

## What it does
- Listens on server-internal `rsg-log:server:CreateLog(channel, title, color, msg, tagEveryone?)` (`AddEventHandler` only; not exposed as a client net event).
- Formats each entry onto a single sanitized line (newlines and control characters stripped; tolerates `nil` or non-string arguments).
- Prints `[fh_log] <line>` to the server console and appends `<line>` to `server/logs/audit.log` (creating `server/logs/` if missing).

## Load order
Ensured in `server/server.cfg` right after `oxmysql` / `ox_lib` and before `rsg-core`, `fh_inventory`, and `rsg-chat`.

## Tests
Formatter spec: `spec/fh_log_spec.lua`.
