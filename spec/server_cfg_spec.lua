-- Run from repo root: `lua spec/server_cfg_spec.lua` (or via tools/run-specs.py).
-- The Cfx cfg parser splits on ';' even inside '#' comments, so the text after it runs as a command
-- ("No such command ..."). No comment line in server/server.cfg may contain ';'.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq

describe('server.cfg', function()
    it('no comment line contains a semicolon', function()
        local f = assert(io.open(here .. '../server/server.cfg', 'r'))
        local bad, n = {}, 0
        for line in f:lines() do
            n = n + 1
            if line:match('^%s*#') and line:find(';', 1, true) then bad[#bad + 1] = n .. ': ' .. line end
        end
        f:close()
        eq('', table.concat(bad, '\n'))
    end)
end)

T.finish()
