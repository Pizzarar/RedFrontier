-- Thin client wrapper around FhGroundSnap (shared/ground_snap.lua). Only this file calls the probe natives.
-- FhSnap.groundZAt(id, x, y, z, above) -> the real ground z once the area has streamed in, else the hint z; on
-- fallback it logs `fh:world:unsnapped <id>` once per id (FhGroundSnap.markUnsnapped). `above` is the probe start
-- offset above z (downward-only ray). Second return = true when the ground was really probed, false on the hint
-- fallback (fh_homestead /fh_plotcheck reads it; every other caller takes the first value only). Default FhGroundSnap.PROBE_ABOVE, or FhGroundSnap.SPAWN_PROBE_ABOVE for spawns.
-- Natives (unverified in-game, same pattern already used in the repo): RequestCollisionAtCoord,
-- GetGroundZFor_3dCoord (rsg-core/client/functions.lua GetGroundZCoord, spikes/spk_camp/client.lua groundZ).
FhSnap = FhSnap or {}

function FhSnap.groundZAt(id, x, y, z, above)
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return z, false end
    x, y, z = x + 0.0, y + 0.0, z + 0.0
    local offset = (type(above) == 'number' and above) or FhGroundSnap.PROBE_ABOVE
    RequestCollisionAtCoord(x, y, z)
    local startZ = (z + offset) + 0.0
    local deadline = GetGameTimer() + FhGroundSnap.TIMEOUT_MS
    local attempt = 0
    while FhGroundSnap.shouldRetry(attempt, FhGroundSnap.MAX_RETRIES, GetGameTimer(), deadline) do
        attempt = attempt + 1
        local found, gz = GetGroundZFor_3dCoord(x, y, startZ, false)
        if FhGroundSnap.usable(found, gz) then return gz, true end
        Wait(FhGroundSnap.RETRY_MS)
    end
    if FhGroundSnap.markUnsnapped(id) then
        print(('fh:world:unsnapped %s'):format(tostring(id)))
    end
    return z, false
end

-- fh_tp place-id arrival snap (world-03 J): the server teleports to the z-hint, then asks this client to snap to the
-- real ground on the same FhSnap path client/spawn.lua uses. No new probe native. `verified` picks the probe depth
-- (verified/town lots use the tight downward probe, unverified claims/camps the wide one), same as spawn placement.
FH.onNet('fh:tp:snap', function(d)
    if type(d) ~= 'table' or type(d.x) ~= 'number' or type(d.y) ~= 'number' or type(d.z) ~= 'number' then return end
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end
    local above = FhGroundSnap.probeAboveFor({ verified = d.verified })
    local z = FhGroundSnap.snapZ(d.z + 0.0, FhSnap.groundZAt(d.id, d.x, d.y, d.z, above), FhGroundSnap.SNAP_TOLERANCE)
    SetEntityCoords(ped, d.x + 0.0, d.y + 0.0, z, false, false, false, false)
end)
