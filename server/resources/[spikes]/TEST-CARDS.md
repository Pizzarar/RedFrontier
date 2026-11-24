# Spike test cards (S1 → S6), owner: Aub

Checkout: `<repo-root>` (the same one you start the server from with `tools/start-server.ps1`). The spikes live in `server/resources/[spikes]/`. They are **not** in server.cfg, so you start each one by hand.
How: in the **server console window** type `ensure spk_<name>`. In game, press T and type the `/spk_...` command. Console output shows in the server window, and client output shows in F8.
Each card takes 5 minutes or less. When you're done, open `server/resources/[spikes]/spk_<name>/README.md` and fill in the last line: `RESULT: GO|NO-GO|PARTIAL — <why>` (or just tell the Spikes lead).

## S1 · spk_camp (camp spawn + ownership), the M1 blocker
- Start: `ensure spk_camp`
- Test: run `/spk_camp` on a road. **Read the two path lines first**: server CreatePed and server CreateVehicle, each OK or FAILED. Ride 300m away and back, then `/spk_camp status`. Disconnect, rejoin, `/spk_camp status`: same netIds, no dupes, owner changed. Shoot one outlaw, `/spk_camp status`: it shows DEAD. Finish with `/spk_camp clear`.
- GO: 4 outlaws + props spawn once; no duplicates on rejoin; the camp survives you leaving; the kill shows in status.
- RESULT: `spk_camp/README.md` last line. Also copy the two path lines.

## S2 · spk_chase (mounted wagon chase)
- Start: `ensure spk_chase` (and `ensure spk_wheel` if you need a wagon: `/spk_wheel wagon`)
- Test: drive a wagon on a road, run `/spk_chase`, and drive for 60s (some of it off-road). Watch the per-5s `R1 distm ...` lines and any STALL/BUNCH flags. Finish with `/spk_chase clear`.
- GO: 3 riders keep pace and shoot for 60s; ~0 STALL/BUNCH flags.
- RESULT: `spk_chase/README.md` last line.

## S3 · spk_wheel (wheel break)
- Start: `ensure spk_wheel`
- Test: if you have no wagon, run `/spk_wheel wagon`. Then run `/spk_wheel` and drive ~20s: does one wheel break and the wagon slow? Then `/spk_wheel fix`. If nothing breaks, try `/spk_wheel 1`..`3` and `/spk_wheel alt`.
- GO: one wheel visibly breaks and slows the wagon; fix restores it.
- RESULT: `spk_wheel/README.md` last line.

## S4 · spk_pelt (pelt quality)
- Start: `ensure spk_pelt`
- Test: `/spk_pelt` spawns 2 deer ~20m ahead. Shoot deer A in the head and deer B in the body, skin both, then read F8 and the notifications (`quality=` and `lastBone` for each).
- GO: quality is readable and differs between the head shot and the body shot.
- RESULT: `spk_pelt/README.md` last line.

## S5 · spk_wear (weapon wear)
- Start: `ensure spk_wear`
- Test: draw a gun and run `/spk_wear get`. Fire 50 rounds, then `/spk_wear get` again: did degradation/dirt/soot rise? Then `/spk_wear set 0.8`, holster and redraw, and `/spk_wear get` once more.
- GO: per-weapon degradation can be both read and set.
- RESULT: `spk_wear/README.md` last line.

## S6 · spk_herb (herb patch cue)
- Start: `ensure spk_herb`
- Test: run `/spk_herb props` — 6 candidate herb models spawn in a line 2m apart ~4m in front of you; read the `[n] <model>` lines (a model RedM doesn't know prints `FAIL`). Run `/spk_herb blip` — a blip cycles 4 candidate plant sprites every 3s, printing which one is showing. Finish with `/spk_herb clear`.
- GO: name the herb model (index) and the blip sprite that looked right.
- RESULT: `spk_herb/README.md` last line.
