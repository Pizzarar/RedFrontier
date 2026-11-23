# Core plan 02 · B7 fix brief (rebuilt 2026-11-23 after C2 cutover)

The original `notes/b7-fix-brief.md` was lost in the cutover. The Gemini review transcript (rn-823b275a1998 / rn-8285c835cc70) is also gone.
This brief is rebuilt from the review's logged summary and plan core-02.

- Branch: `core-b7` (worktree `~/.vibesquad/worktrees/RedFrontier/core-b7`), rebased on main 8b6b1a7 → tip 46da4cc (was 9bad7c4 before the rebase).
- Review: Gemini **FAIL 1/0/2** on 9bad7c4. Logged summary: "stale balance snapshot in fh_economy:charge across MySQL await yield (1 crit); 2 minor; 17 specs/316 tests pass".
- stakes=tierA-invariant (ledger debit).

## Fix 1 (crit): charge read-modify-write across the insert yield
`fh_economy/server/main.lua` `charge()` captures `Player = getPlayer(src)` **before** `MySQL.insert.await` yields, and
`FhLedgerLogic.runCharge` (`shared/ledger_logic.lua`) uses that snapshot for the re-check and RemoveMoney after the yield.
The contract must hold with no exceptions:
- Any number of concurrent `charge` calls for the same character never take more than the balance and never go negative.
- Every money removal has exactly one ledger row, and no row is left behind without a removal (a failed void is warned, as in `pay`).
- If the player dropped or switched character during the yield, the charge fails closed: it voids its row and takes no money from a stale Player object.

Required:
- After every yield, re-fetch the player and check the citizenid is still the same. Never act on the object captured before the yield.
- Serialize `charge` per citizenid (an in-flight guard or queue inside fh_economy), so two charges can't interleave their check, insert and remove.
  Say how a second concurrent caller is handled: it waits, or it fails with a named error. Spec that choice.
- Apply the same post-yield re-fetch to `pay` if it has the same stale-Player pattern. That is the same root cause in the same unit.
- Specs in `spec/ledger_logic_spec.lua` / `spec/fh_economy_server_spec.lua`: two interleaved charges where only one is affordable (exactly one succeeds and exactly one row survives); a player dropped mid-yield; a character switched mid-yield; a failed void warns.

## Fix 2+3 (two lows): titles unrecoverable
The reviewer logged "2 minor" without titles. Self-audit the full B7 diff (`git diff 8b6b1a7...core-b7`) against core-02's done-check and fix the two most likely low-severity gaps.
Candidates: the README export docs match the real signatures and errors for charge, getRep, removeItem and registerItems; the getRep input validation (non-number src, unknown region); the removeItem error strings match the plan (`fh_not_enough`, no partial removal).
List what you fixed in your final message so the re-review can check it.

## Out of scope
fh_heat itself, wagon tiers, item gameplay, B-access files (`access.lua`, `access_rules.lua`, server.cfg, tools/*.ps1).

## Verification
`python3 tools/run-specs.py` cannot run on the forge right now (no Python lupa; the Overlord flagged it, owner sudo needed).
Do NOT install workarounds (no pip/venv/get-pip). Write the specs anyway. Report "specs written, not run: lupa missing" plus the spec names.
The lead runs the full spec suite before merge once lupa is installed.
