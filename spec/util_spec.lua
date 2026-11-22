local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same

local util = require('util')

describe('fh_core shared/util', function()
  describe('clamp', function()
    it('returns the value inside range', function() eq(5, util.clamp(5, 0, 10)) end)
    it('clamps below and above', function()
      eq(0, util.clamp(-3, 0, 10))
      eq(10, util.clamp(99, 0, 10))
    end)
    it('tolerates swapped bounds', function() eq(4, util.clamp(4, 10, 0)) end)
  end)

  describe('deepCopy', function()
    it('copies nested tables without aliasing', function()
      local a = { x = { y = 1 }, list = { 1, 2 } }
      local b = util.deepCopy(a)
      same(a, b)
      assert(a.x ~= b.x, 'nested table aliased')
      b.x.y = 2
      eq(1, a.x.y)
    end)
    it('handles cycles', function()
      local a = {}; a.self = a
      local b = util.deepCopy(a)
      eq(b, b.self)
    end)
  end)
end)

T.finish()
