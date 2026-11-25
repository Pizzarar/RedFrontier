-- SERVER ONLY (fxmanifest server_scripts, never shared_scripts / client_scripts / files): the exact treasure lead
-- spots and their hints. config.lua is a shared script that every client downloads, so it only names a spot by its
-- opaque id (stock[*].leads[*].lead = '<id>'), and a bought lead's item info is just { lead = '<id>' }. The server
-- resolves the id here for the dig distance check and for the grid-rounded area it sends (server/leads.lua).
-- Ids must not describe the spot. Coords are APPROXIMATE (Heartlands): verify in game and adjust. Moving a spot later
-- moves it for every lead already sold with that id; removing an id makes those leads undiggable.
FhFenceLeadSpots = {
    lead_hl_01 = { coords = { x = -520.0, y = 910.0, z = 120.0 }, hint = 'Where the old rail line meets the creek.' },
    lead_hl_02 = { coords = { x = -60.0, y = 760.0, z = 116.0 }, hint = 'Under the split oak east of the ridge.' },
}
