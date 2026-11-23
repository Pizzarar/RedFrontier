# Quests

Quests are jobs from a board, three one-time family stories, and the intro. Everything is built, but **none of it is checked in game yet** (unverified). Rewards pay money and reputation once, through [Economy](fh_economy.md).

## The jobs board
- Type `/jobs` to open the board. It works anywhere, and there is also a notice-board spot in the Heartlands.
- The board holds 3 to 5 offers and refreshes every 60 minutes.
- Job types:
  - **Hunt request:** sell a pelt of the star rating asked for. See [Hunting](fh_hunting.md).
  - **Camp clear:** clear a named outlaw camp. Everyone near the camp when it falls gets credit. See [Zones](fh_zones.md).
  - **Bounty:** a wanted NPC spawns for you. Kill them and you are paid, whoever lands the shot.
  - **Freight:** haul trade goods to another region. See [Roads](roads.md).
- The same job can't be taken again for 60 minutes after you finish it (freight: 30).
- Only the Heartlands has job offers today.

## Journal
`/journal` lists your active quests and your history. You can abandon an active quest there (click twice to confirm).

## Family questlines
Talk to the giver within 5 m. Each line is three steps, in order, ending with a report back.

| Family | Steps | Reward |
|---|---|---|
| Hale and Daughters: A Roof Over Your Head | claim a plot, earn $15 or more in one payment, report back | $40, +5 rep |
| Marrow's Debt: Smoke on the Ridge | clear an outlaw camp, sell 2 pelts, report back | $60, +8 rep |
| Whitlock's Ghost: The Bear of Bear Hollow | sell a 2-star or better pelt, finish the Legendary Bear hunt, report back | $120, +12 rep |

Dialogue is plain text pop-ups. No cutscenes or voice.

## Good to know
- A quest only counts what you do yourself. Nobody else's kill or sale advances yours (camp clears also credit players near the camp).
- A reward is paid once. If you are offline when it is due, it waits for your next login.
- **Item rewards are not delivered yet.** Money and rep still pay.
- Giver and bounty positions are guesses (unverified).

See also: [Homestead](fh_homestead.md) · [Wiki index](../README.md)

Sources:
- `server/resources/[fh]/fh_quests/README.md`
- `server/resources/[fh]/fh_quests/data/families/whitlock.lua`
- `server/resources/[fh]/fh_quests/shared/jobtypes.lua`
- `server/resources/[fh]/fh_quests/client/board.lua`
- `server/resources/[fh]/fh_quests/client/journal.lua`
- `server/resources/[fh]/fh_trade/config.lua`
