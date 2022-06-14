local M = {}

local uv = vim.loop

local function async(fn)
    return function()
        local thread = coroutine.create(fn)
        local status, ret = coroutine.resume(thread)
        assert(status, ret)
    end
end

local function asyncify(fn)
    local current_co = coroutine.running()
    local callback = function(...)
        local status, ret = coroutine.resume(current_co, ...)
        assert(status, ret)
    end

    fn(callback)
end

local function await()
    return coroutine.yield()
end

local function spawn(name, opts)
    return asyncify(function(callback)
        uv.spawn(name, opts, callback)
    end)
end

M.setup = async(function()
    local code, signal = await(spawn("touch", { args = { "/home/john/foo" } }))
    print("yes!", code, signal)
end)

return M
