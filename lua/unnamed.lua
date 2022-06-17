local M = {}

-- https://github.com/luvit/luv/blob/master/docs.md
local uv = vim.loop

local rootPath = "/home/john/.config/nvim/unnamed/" -- TODO: make this configurable
local repoPath = rootPath .. "repo/"
local compilePath = rootPath .. "compiled/"

local compile_blacklist = { ".git" }

local function pack(...)
    return { n = select("#", ...), ... }
end

local function str_starts_with(str, starting)
    return starting == "" or str:sub(1, #starting) == starting
end

local function str_ends_with(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

local function array_contains(value, array)
    for _, v in ipairs(array) do
        if v == value then
            return true
        end
    end

    return false
end

local function join_array(arrays)
    local ret = {}
    for _, array in ipairs(arrays) do
        for _, v in ipairs(array) do
            table.insert(ret, v)
        end
    end
    return ret
end

local function join_str(strarray, delimiter)
    local ret = ""
    for i, s in ipairs(strarray) do
        ret = ret .. s
        if i ~= #strarray then
            ret = ret .. (delimiter or " ")
        end
    end
    return ret
end

local function str_trim_prefix(str, prefix)
    if str_starts_with(str, prefix) then
        return str:sub(#prefix + 1)
    else
        return str
    end
end

-- { trailing_slash: bool (default = true) }
local function join_path(elements, opts)
    local ret = ""

    for _, element in ipairs(elements) do
        ret = ret .. element
        if not str_ends_with(ret, "/") then
            ret = ret .. "/"
        end
    end

    if opts and not opts.trailing_slash and str_ends_with(ret, "/") then
        ret = ret:sub(0, -2)
    end

    return ret
end

local function coroutine_fail_fmt(ret, thread)
    return string.format(
        "\n\n### coroutine stacktrace ###\n%s\n%s\n### coroutine stacktrace until here ###\n",
        ret,
        debug.traceback(thread)
    )
end

local function async(fn)
    return function(...)
        local thread = coroutine.create(fn)
        local status, ret = coroutine.resume(thread, ...)
        assert(status, coroutine_fail_fmt(ret, thread))
    end
end

-- resume_ctx: dict {
--     ret: array,
--     deferred: Option<fn>
-- }

local function asyncify(fn)
    local current_co = coroutine.running()
    local callback = function(resume_ctx)
        local status, ret = coroutine.resume(current_co, resume_ctx)
        assert(status, coroutine_fail_fmt(ret, current_co))
    end

    return fn(callback)
end

local function await(...)
    local ret = { ... }
    local resume_ctx = coroutine.yield()

    if resume_ctx.deferred then
        resume_ctx.deferred()
    end

    return unpack(join_array({ ret, resume_ctx.ret or {} }))
end

local function spawn(name, opts)
    assert(name and opts)

    return asyncify(function(wake)
        local callback = function(code, signal)
            local deferred = function()
                if code == 0 then
                    return
                end

                local msg = string.format(
                    "command '%s' failed with status %d",
                    join_str(join_array({ { name }, opts.args or {} })),
                    code
                )

                error(msg)
            end

            wake({
                ret = { code, signal },
                deferred = deferred,
            })
        end

        local handle, pid = uv.spawn(name, opts, callback)
        assert(handle, pid) -- fails here when executable is not found (ENOENT), for example
        return handle, pid
    end)
end

local function list_files_recursively(path)
    local stat, err = uv.fs_stat(path)
    assert(stat, err)
    assert(stat.type == "directory", "path must point to directory")

    local scanner, err = uv.fs_scandir(path)
    assert(scanner, err)

    local ret = {}

    while true do
        local name, type = uv.fs_scandir_next(scanner)
        if name == nil then
            break
        end
        if not name then
            err(name)
        end

        if not array_contains(name, compile_blacklist) then
            if type == "file" then
                table.insert(ret, join_path({ path, name }, { trailing_slash = false }))
            elseif type == "directory" then
                for _, file in ipairs(list_files_recursively(join_path({ path, name }))) do
                    table.insert(ret, file)
                end
            end
        end
    end

    return ret
end

local function compile(repos)
    local symlink_table = {}
    for _, repo in ipairs(repos) do
        local fullpath = join_path({ repoPath, repo })
        local repo_files = list_files_recursively(fullpath)

        for _, file in ipairs(repo_files) do
            local relative_path = str_trim_prefix(file, fullpath)
            symlink_table[relative_path] = file
        end
    end

    for compiledFilePath, srcPath in pairs(symlink_table) do
        local compiledFullPath = join_path({ compilePath, compiledFilePath }, { trailing_slash = false })

        local iserr, err = await(
            spawn("sh", { args = { "-c", string.format("mkdir -p $(dirname '%s')", compiledFullPath) } })
        )
        assert(iserr, err)

        local iserr, err = uv.fs_symlink(compiledFullPath, srcPath)
        assert(iserr, err)
    end
end

M.setup = async(function(repos)
    for i, repo in ipairs(repos) do
        local clonePath = join_path({ repoPath, repo })
        local stat = uv.fs_stat(clonePath) -- TODO: proper detectation (check whether if `git status` successes?)

        if stat == nil then
            print(string.format("cloning %s ", repo))

            await(spawn("git", { args = { "clone", "https://github.com/" .. repo, clonePath } }))

            print(string.format("cloning %s done", repo))
        end
    end

    compile(repos)
end)

return M
