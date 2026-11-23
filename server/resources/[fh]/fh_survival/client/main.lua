-- fh_survival client stub (S2). S5 adds the sluggish effect; @ui may listen to fh:survival:state.
RegisterNetEvent('fh:survival:state', function(_state)
    -- payload { level = 0..3, missing = { need names } }; no effect yet
end)
