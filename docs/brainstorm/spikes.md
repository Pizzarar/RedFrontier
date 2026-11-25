# Brainstorm Summary · SPIKES (`spikes`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: Spikes
- Lead: Spikes Lead · spk_herb
- Workers: 0

## Done when
- S1–S5 each have a RESULT line (GO/NO-GO/PARTIAL) from Aub in-game, and proven natives are handed to Core for natives.md.

## Decided
- Plan: docs/brainstorm/plans/spikes-01-probes.md (S1 camp+ownership → S2 wagon chase → S3 wheel → S4 pelt → S5 wear).
- No own server; run on @core dev server. One `spk_<name>` resource per spike, ensured by hand, one-line README test, ≤5 min.
- ox_lib only, no RSG inventory calls. Natives listed with hash; Core folds into natives.md.

- Path confirmed by Core: server/resources/[spikes]/spk_<name>/; natives via Core lead into fh_core/docs/natives.md. Server boots at end of Core B1.
- S1 default = owner drop/rejoin migration.

- S1–S5 BUILT on spikes/probes (ae6c530 wheel, 7cd229d pelt, 6a4098e wear, 8e4a69c camp, d6c0aad chase), unpushed, untested. 90 natives hash-checked.
- FINDING (verified): RedM server has no CREATE_PED/CREATE_OBJECT_NO_OFFSET (fivem ServerSetters.cpp #ifndef STATE_RDR3 L4–517). Spec :124 → server decides/owns state, client creates networked entity, server adopts netId. Sent to Core Buddy.

- Core confirmed the finding and added a spawn-request contract to core-01 B4 (provisional until S1). Server CreateVehicle is also RDR3-excluded per source (L312/L343). S1 gets a pcall CreateVehicle probe; S1's path lines go to Core when run.

- Core B1 server on core/b1-boot (ee8eef5): boots to licence check; needs Aub's Cfx key in server/secrets.cfg (OWNER-STEPS.md). Lead rebases spikes onto core/b1-boot and stages S1–S5 test cards behind Core's 'Started resource' ping.

- spikes/probes rebased onto core/b1-boot (ee8eef5 + 5 spikes + 67de323 cards in server/resources/[spikes]/TEST-CARDS.md). Old tip kept as spikes/probes-orphan. Wagon spawn `/spk_wheel wagon` added for S2/S3. Core lead merges core/b1-boot to main after Aub's first keyed join, then merges reviewed spikes; cards point at the main checkout.

- Additions in: cbc55d6 (S1 server CreateVehicle probe), 8e992ea (/spk_wheel wagon). Gemini review Spk5 on ee8eef5..8e992ea; on PASS lead sends tip to Core lead for merge.

- Gemini review PASS w/ nits (1 major: wrong CreateVehicle hash in S1 README). Spk6 fixing that + S4 GetHashKey line + S1/S2 AI weapon holster flag. Skipped 2 throwaway nits. Then tip to Core lead.

- Build+review block PASS (2026-11-22): spikes/probes tip 4d11954, 22 files all under [spikes]/ (Buddy verified). Handed to Core lead; merges to main after Aub's keyed join. Remaining: in-game RESULTs.

- Spikes merged to local main (382de5e; main now 32527fe, 4d11954 is ancestor, verified). Not pushed. Primary checkout on main; cards at server/resources/[spikes]/TEST-CARDS.md.

- idea-847 spk_herb: plan docs/brainstorm/plans/spikes-02-herb.md. Client-local plant props + blip probe (S6). Not gated on fh_spike_gated (that is S1/S2 ownership); crafting wires the cue only after GO. crafting-herb-spike branch empty (verified). Handed to Spikes Lead rn-3095b3717f66 (2026-11-24).

- S7 spk_outfit for Progression idea-891: plan spikes-03-outfit.md, client-only, re-apply on rsg ApplySkin; named S7 (their 'S1'). Handed to lead rn-3095b3717f66 2026-11-25.

## Open
- S6 RESULT from Aub (herb model index + blip sprite).
- Does Aub have a 2nd RedM account? (adds true 2-client S1 check)

## In flight
- PASS spk_outfit S7 O1-O3 (plan spikes-03-outfit complete): merged main ff 23e32fe, fresh-Gemini PASS 0/0/1, G5 0 unknown, contracts 0 findings. Next: S7 card to Aub; RESULT -> Progression Buddy rn-515b14f1fb08 + Pro2, natives -> Core.
- S7 O1 PASS 9a93a05 on spikes-outfit (Gemini build, 4 files [spikes]/); O2 Gemini review PASS 0/0/1 (L1 nit skipped); rebased 23e32fe on main 95177a0, slot requested Red4 -> O3 merge (lead rn-3095b3717f66). RESULT goes to Progression rn-515b14f1fb08 + Pro2.
- spk_herb MERGED main 1680b5b (+brief d492bfe), Gemini PASS 0/0/0. S6 card relayed to Aub 2026-11-25. On GO: inbox @crafting (model+sprite), natives to Core.
- PARKED forge freeze 2026-11-23: no unit running; spikes in main (4d11954), cards held for keyed boot; worktree spikes-probes clean. Resume = relay TEST-CARDS.md to Aub after Cor2 boot ping.
- PASS S1-S5 build+review: spikes/probes 4d11954 (on core/b1-boot ee8eef5), Gemini PASS-WITH-NITS, 3 fixed, 2 nits skipped; Core lead merges to main; in-game RESULTs pending Aub.
- Next: Gemini review of all 5 (after machine restart) → test cards to Aub once Core server boots.
- Workaround: orphan branch spikes/probes; lead rebases onto main once Core lands it. VS bug idea-561.
- Pushes need owner OK (personal repo).
