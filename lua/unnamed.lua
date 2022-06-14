local M = {}

local uv = vim.loop

local rootPath = "/home/john/.config/nvim/unnamed/" -- TODO: make this configurable
local repoPath = rootPath .. "repo/"
local compilePath = rootPath .. "compiled/"

local function pack(...)
    return {n = select("#", ...), ...}
end

local function async(fn)
    return function(...)
        local thread = coroutine.create(fn)
        local status, ret = coroutine.resume(thread, ...)
        assert(status, ret)
    end
end

local function asyncify(fn)
    local current_co = coroutine.running()
    local callback = function(...)
        local status, ret = coroutine.resume(current_co, ...)
        assert(status, ret)
    end

    return fn(callback)
end

local function await(...)
    local ret = { ... }
    local coroutine_ret = pack(coroutine.yield())

    -- join coroutine_ret into ret
    for i, v in ipairs(coroutine_ret) do
        table.insert(ret, v)
    end

    return unpack(ret)
end

local function spawn(name, opts)
    return asyncify(function(callback)
        local handle, pid = uv.spawn(name, opts, callback)
        assert(handle, pid) -- fails here when executable is not found (ENOENT), for example
        return handle, pid
    end)
end

M.setup = async(function(repos)
    for i, repo in ipairs(repos) do
        print(string.format("cloning %s ", repo))

        local _, _, code = await(spawn("git", { args = { "clone", "https://github.com/" .. repo, repoPath .. repo } }))
        if code ~= 0 then
            error(string.format("git exited with code %d", code))
        end

        print(string.format("cloning %s done", repo))
    end
end)

return M
