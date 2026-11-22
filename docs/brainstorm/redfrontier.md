# Brainstorm Summary · REDFRONTIER (`redfrontier`)

> Rolling team brief (< ~5k tokens). Updated on every decision.

## Who's here
- Brainstorm: RiffBot
- Lead: Overlord
- Workers: 0

## Done when
- (what makes this team finished)

## Decided
- 2026-11-22: optimize for owner time-to-first-play. @core carries M0 straight into the M1 slice; @spikes = 5-min in-game probes on Core's dev server.
- 2026-11-22: machine split. DevPC hosts repo + FXServer + txAdmin + MariaDB. Main PC runs RDR2 + RedM client only and connects on port 30120.

## Open
- (none recorded yet)

## In flight
- (none recorded yet)

## Teams
- @core (rn-bc8bcb7f7c98): designing. Server you can join, then §4 contracts, then M1 slice.
- @spikes (rn-5b33cb75dbfb): designing. Probes: camp spawn/migration, wagon chase, wheel break, pelt quality, weapon wear.

## Unsplit threads
- Spec: docs/FRONTIER_HOMESTEAD_SPEC.md (owner, 2026-11-22). Priority #3 behind VibeSquad, EFI.
- Hub feasibility read (2026-11-22): M0 + M1 slice feasible; biggest unknowns = rsg-inventory vs fh_core container ownership, owner-as-only-tester bottleneck, mounted wagon chase AI, homestead "clearing" of world objects.
- L1–L10 feature lanes: wait until @core locks §4 contracts.
