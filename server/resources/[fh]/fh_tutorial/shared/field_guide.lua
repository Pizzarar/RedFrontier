-- fh_tutorial field guide content (guide-02 T2): read-only in-game help pages for the fh_ui `fieldguide` screen.
-- Every entry is condensed strictly from its docs/wiki/systems/*.md page (which are verified against code).
-- One entry per docs/wiki/systems/*.md page; checked by tools/check-wiki.py and spec/fieldguide_spec.lua.

FhFieldGuide = {
    entries = {
        {
            id = 'tutorial',
            title = 'Tutorial & Field Guide',
            lines = {
                'A twelve-step intro starts automatically the first time a new character loads.',
                'It is completely optional, never blocks other systems, and can be skipped any time.',
                'Steps with a destination draw a yellow GPS route; progress is saved per character by step id.',
                'Use /guide to open this read-only field guide at any time.',
            },
            controls = {
                '/tutorial: show current step',
                '/tutorial skip: stop tutorial',
                '/tutorial restart: replay from step 1',
                '/guide [id]: open field guide',
            },
            wiki_path = 'docs/wiki/systems/tutorial.md',
        },
        {
            id = 'survival',
            title = 'Survival & Needs',
            lines = {
                'Needs (food, water, rest, clean, warmth) are never lethal; missing them only makes you sluggish (levels 0-3).',
                'Eat food for well_fed (60 min) and drink from a 5-charge canteen for hydrated (45 min).',
                'Use a bedroll or homestead bed for rested (120 min), wash in water for clean (90 min), and stand near a fire for warm (20 min).',
                'New characters get a 10-minute grace period, and need timers pause while you are offline.',
            },
            controls = {
                '/refill: refill canteen in water',
                '/wash: wash in water (5 min cooldown)',
            },
            wiki_path = 'docs/wiki/systems/survival.md',
        },
        {
            id = 'inventory',
            title = 'Inventory',
            lines = {
                'Your inventory splits into a 5-slot hotbar (8 kg cap) and a backpack (default 25 slots, 35 kg total).',
                'Drag to move, swap or merge; Shift + drag moves half; Ctrl + click moves to the other panel.',
                'Double-click to use an item, or right-click for Use, Give, Drop and Trash (asks to confirm).',
                'Use the search box and Sort button to organize panels; push-to-talk still works while open.',
            },
            controls = {
                'I: open inventory',
                'Z: show hotbar',
                '1-5: use hotbar slot',
            },
            wiki_path = 'docs/wiki/systems/fh_inventory.md',
        },
        {
            id = 'core',
            title = 'Containers & Saddlebag',
            lines = {
                'Items are pocket, bulky or cargo: backpack and hotbar take pocket only; saddlebag takes pocket and bulky; wagons and chests take all three.',
                'World containers must be within 3.5 m to open (wagons 5 m).',
                'Each character has one 20-slot, 60 kg saddlebag; use /saddlebag on or next to a horse within 3.5 m.',
                'Weapons track condition (0-100) and pelts track quality stars (1-3).',
            },
            controls = {
                '/saddlebag: open saddlebag near a horse',
                '/saddlebag in|out <slot> [amount]: move stack with open container',
            },
            wiki_path = 'docs/wiki/systems/fh_core.md',
        },
        {
            id = 'homestead',
            title = 'Homestead',
            lines = {
                'Claim one fixed 25 m plot per character (four in the Heartlands, four in Scarlett Meadows).',
                'Each plot has an owner-only chest that accepts pocket, bulky and cargo items.',
                'Build a cabin, fence, extra chests, trophy wall and crafting stations using cash plus lumber and nails stored in your plot chest.',
                'Built pieces and up to 6 trophies on a trophy wall (max 20 trophy points) add comfort for survival rest.',
            },
            controls = {
                '/fh_claim: claim plot',
                '/fh_unclaim: release plot',
                'E (unverified): open plot chest',
                '/fh_build [slot]: list or build slot',
                '/fh_trophy place|remove <item|id>: manage trophies',
                '/fh_comfort: check comfort',
            },
            wiki_path = 'docs/wiki/systems/fh_homestead.md',
        },
        {
            id = 'crafting',
            title = 'Crafting',
            lines = {
                'Reload revolver or rifle ammo at your homestead workbench, or brew Vigor and Steady tonics at your campfire.',
                'You can only craft on your own plot, within 3 m of the built station.',
                'Crafts are all-or-nothing: if any step fails, taken inputs are returned.',
                'Vigor Tonic grants 1.15 for 10 minutes; Steady Tonic grants 1.10 for 5 minutes.',
            },
            controls = {
                '/fh_craft: list recipes',
                '/fh_craft <recipe>: craft recipe at station',
            },
            wiki_path = 'docs/wiki/systems/crafting.md',
        },
        {
            id = 'gunsmith',
            title = 'Gunsmith',
            lines = {
                'Restore worn weapons at a built workbench on your own plot (within 3 m) using Gun Parts.',
                'Each gun part adds 20 condition, capped by stars: 1 star to 60, 2 stars to 80, 3 stars to 100.',
                'Gun Parts drop from outlaw camps; the fence sells Gunsmith Parts, which are a separate illicit item.',
            },
            controls = {
                '/fh_restore <slot>: restore weapon in open container',
            },
            wiki_path = 'docs/wiki/systems/fh_gunsmith.md',
        },
        {
            id = 'hunting',
            title = 'Hunting & Pelts',
            lines = {
                'Kill an animal, stand within 5 m and use the Skin option (4-second bar); default game skinning gives no pelt.',
                'Hit placement sets stars: head/vital 3 stars, body 2 stars (10% chance of 1), limb/gut/multi-hit/explosives 1 star.',
                'Bulky pelts fit in a saddlebag or wagon; cargo pelts (bear, bison, elk, moose, alligator) need a wagon within 8 m.',
                'Sell pelts from your saddlebag or nearby wagon to the Heartlands Trapper, or pay $25 for the Legendary Bear rumour.',
            },
            controls = {
                'Skin option (within 5 m): skin animal',
                'E (unverified): open trapper sell menu (within 2 m)',
            },
            wiki_path = 'docs/wiki/systems/fh_hunting.md',
        },
        {
            id = 'zones',
            title = 'Outlaw Camps',
            lines = {
                'Outlaw camps sit across the Heartlands, Scarlett Meadows, Bayou Nwa and the Great Plains, each with four outlaws.',
                'Approach within 45 m to wake the camp; kill all four outlaws to clear it and unlock the camp stash.',
                'Loot rolls a Worn Rifle (bulky), Small Safe (bulky), Gun Parts and occasional contraband.',
                'The stash stays open for 10 minutes before the camp resets to idle.',
            },
            controls = {
                'E: open cleared camp stash',
            },
            wiki_path = 'docs/wiki/systems/fh_zones.md',
        },
        {
            id = 'alife',
            title = 'A-Life: Camp Ownership',
            lines = {
                'Clearing an outlaw camp hands control to the local law; a law-held camp stays quiet when you walk in.',
                'Roughly 20-30 minutes later an outlaw squad retakes the camp and makes it hostile again.',
                'Law control eases the region shortage (salt in Heartlands, whiskey in Scarlett Meadows); outlaw retakes raise it.',
            },
            controls = {},
            wiki_path = 'docs/wiki/systems/fh_alife.md',
        },
        {
            id = 'roads',
            title = 'Roads, Wagons & Heat',
            lines = {
                'Three wagon tiers (Cart 120 kg, Wagon 300 kg, Freight 500 kg) haul cargo; full wagons slow by 40% and block fast travel.',
                'Wheels can break under speed or load (40% max speed); repair in 8 s with a hammer and wheel.',
                'Sell Salt, Cloth and Whiskey at Valentine or Rhodes Trade Posts; shortages raise prices and spawn freight jobs on /jobs.',
                'Each faction tracks heat (0-100): Watched at 25, Wanted at 50 (roadblocks), Hunted at 75; heat falls 2/min outside territory.',
                'Pay off faction heat at $4 per point with /paybounty.',
            },
            controls = {
                '/fh_cargo load|unload: move cargo with open chest',
                '/fh_repair: repair broken wagon wheel',
                '/tradepost: sell at trade post',
                '/tradequote: check trade prices',
                '/paybounty [faction] [points]: view or pay heat',
            },
            wiki_path = 'docs/wiki/systems/roads.md',
        },
        {
            id = 'fence',
            title = 'Roving Fence',
            lines = {
                'A travelling fence alternates between the Roadside Fence and Camp-Edge Fence in the Heartlands every 20 minutes.',
                'Always sells bread and water; Heartlands tier 2 unlocks Gunsmith Parts and Saddlery Fittings, tier 3 unlocks Treasure Leads.',
                'Buys Gunsmith Parts ($30) and Saddlery Fittings ($35) for cash.',
                'Treasure Leads are one-off items carrying a hint and a spot.',
            },
            controls = {
                'E: open fence menu (within 6 m)',
            },
            wiki_path = 'docs/wiki/systems/fh_fence.md',
        },
        {
            id = 'quests',
            title = 'Quests & Jobs',
            lines = {
                'Jobs boards in the Heartlands and Scarlett Meadows hold 3-5 offers (hunt, camp clear, bounty, freight) refreshing every 60 minutes.',
                'Three one-time family questlines (Hale, Marrow, Whitlock) start by talking to each giver within 5 m.',
                'Quests count only your own actions (camp clears also credit nearby players) and pay cash and reputation once.',
                'Use /journal to track active quests, review history, or abandon an active quest (click twice to confirm).',
            },
            controls = {
                '/jobs: open nearest jobs board',
                '/journal: open quest journal',
            },
            wiki_path = 'docs/wiki/systems/quests.md',
        },
        {
            id = 'economy',
            title = 'Economy & Reputation',
            lines = {
                'Money is paid in cash and reputation is tracked per region (-10000 to 10000), recorded in a permanent ledger.',
                'Earn cash from pelts, trade goods, freight jobs, the fence and quests; spend it at the fence, on hired hands and rumours.',
                'Payouts and refunds owed while you are offline are queued and delivered on your next login.',
                'Charges never take your balance below 0 (single payout or charge cap is 100000).',
            },
            controls = {},
            wiki_path = 'docs/wiki/systems/fh_economy.md',
        },
        {
            id = 'progression',
            title = 'Regional Progression',
            lines = {
                'Your reputation in a region sets your tier from 1 to 3 (Heartlands: tier 1 floor, tier 2 at 100 rep, tier 3 at 400 rep).',
                'Tier 2 unlocks T2 contracts, T2 wagons, fence rare stock and hiring a ranch hand; tier 3 unlocks fence treasure leads.',
                'An unknown region or unloaded character counts as tier 1.',
            },
            controls = {},
            wiki_path = 'docs/wiki/systems/progression.md',
        },
        {
            id = 'buffs',
            title = 'Buffs',
            lines = {
                'Buffs are timed bonuses; different buffs stack, while re-applying the same buff refreshes its timer and keeps the stronger value.',
                'Active buffs include survival needs (well_fed, hydrated, rested, clean, warm) and crafted tonics (Vigor, Steady).',
                'Buffs are lost when you relog or the server restarts.',
            },
            controls = {},
            wiki_path = 'docs/wiki/systems/fh_buffs.md',
        },
        {
            id = 'death',
            title = 'Death & Drop Bags',
            lines = {
                'On death your hotbar stays with you, while your backpack and saddlebag move into a drop bag at the death spot.',
                'Only you can open your drop bag, within 3.5 m; if both backpack and saddlebag were empty, no bag is created.',
                'Unemptied bags expire and are deleted after 30 minutes, losing anything still inside.',
                'Drop bags survive a server restart.',
            },
            controls = {
                'E (unverified): open your drop bag (within 3.5 m)',
            },
            wiki_path = 'docs/wiki/systems/fh_death.md',
        },
        {
            id = 'hands',
            title = 'Hired Hands',
            lines = {
                'The ranch hand tops up your homestead chest with feed (up to 40, at most 10 per working tick).',
                'Wages are $5 cash every 10 minutes; missing 3 wage ticks in a row makes the hand quit.',
                'Requires the Heartlands tier-2 Hire a hand unlock (no player hire command is wired yet).',
            },
            controls = {},
            wiki_path = 'docs/wiki/systems/fh_hands.md',
        },
        {
            id = 'ui',
            title = 'UI, Map Blips & /where',
            lines = {
                'Interactive panels take your mouse and close with Esc; passive HUD widgets (buffs, heat, bags) never take focus.',
                'Map blips mark homestead plots, trade posts, the trapper, quest givers, jobs boards, outlaw camps, stations and fence stops.',
                'Use /where to list places by distance or /where <kind> to mark the nearest one with a destination blip.',
                'Clicking faster than 5 actions per second is rate-limited.',
            },
            controls = {
                'Esc: close interactive screen',
                '/where: list findable places',
                '/where <kind>: mark nearest plot, tradepost, trapper, camp, board, giver, station or fence',
            },
            wiki_path = 'docs/wiki/systems/fh_ui.md',
        },
    },
}

return FhFieldGuide
