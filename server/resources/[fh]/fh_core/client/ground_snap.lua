-- Thin client wrapper around FhGroundSnap (shared/ground_snap.lua). Only this file calls the probe natives.
-- FhSnap.groundZAt(id, x, y, z) -> the real ground z once the area has streamed in, else the hint z; on fallback
-- it logs `fh:world:unsnapped <id>` once per id (FhGroundSnap.markUnsnapped).
-- Natives (unverified in-game, same pattern already used in the repo): RequestCollisionAtCoord,
-- GetGroundZFor_3dCoord (rsg-core/client/functions.lua GetGroundZCoord, spikes/spk_camp/client.lua groundZ).
FhSnap = FhSnap or {}

function FhSnap.groundZAt(id, x, y, z)
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return z end
    RequestCollisionAtCoord(x, y, z)
    local above = z + FhGroundSnap.PROBE_ABOVE
    local deadline = GetGameTimer() + FhGroundSnap.TIMEOUT_MS
    local attempt = 0
    while FhGroundSnap.shouldRetry(attempt, FhGroundSnap.MAX_RETRIES, GetGameTimer(), deadline) do
        attempt = attempt + 1
        local found, gz = GetGroundZFor_3dCoord(x, y, above, false)
        if FhGroundSnap.usable(found, gz) then return gz end
        Wait(FhGroundSnap.RETRY_MS)
    end
    if FhGroundSnap.markUnsnapped(id) then
        print(('fh:world:unsnapped %s'):format(tostring(id)))
    end
    return z
end
