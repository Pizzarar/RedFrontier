-- Stub: client-side buff effects are not implemented yet (server decides, client displays).
-- Later lanes will hook 'fh:buffs:sync' here to apply visual/stat effects.
FH.onNet('fh:buffs:sync', function(_active)
    -- intentionally empty
end)
