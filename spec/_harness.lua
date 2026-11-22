-- Tiny runner shim so a spec file works as `lua spec/<file>.lua` and under busted.
-- Not named *_spec so busted doesn't treat it as a spec.
package.path = table.concat({
    './server/resources/[fh]/fh_core/shared/?.lua',
    './server/resources/[fh]/fh_economy/shared/?.lua',
    './server/resources/[fh]/fh_buffs/shared/?.lua',
    './spec/?.lua',
    package.path,
}, ';')

local H = {}

---Register a named case: busted `it` when available, otherwise run immediately (assert failure aborts).
function H.case(name, fn)
    if type(_G.it) == 'function' then
        _G.it(name, fn)
    else
        fn()
        print('ok - ' .. name)
    end
end

return H
