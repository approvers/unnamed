local M = {}

-- https://github.com/luvit/luv/blob/master/docs.md
local uv = vim.loop

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
local function array_push(array, value)
    array[#array+1] = value
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
            ret = ret .. delimiter
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

-- { trailing_slash: bool (default = false) }
local function join_path(elements, opts)
    local ret = ""

    for _, element in ipairs(elements) do
        ret = ret .. element
        if not str_ends_with(ret, "/") then
            ret = ret .. "/"
        end
    end

    if (not opts or (opts and not opts.trailing_slash)) and str_ends_with(ret, "/") then
        ret = ret:sub(0, -2)
    end

    return ret
end

local function join_path_dir(elements)
    return join_path(elements, { trailing_slash = true })
end

local function dirname(str)
    return str:match("(.*/)")
end

local function dedup_array(array)
    local map = {}
    for i, v in ipairs(array) do
        map[v] = 1
    end

    local ret = {}
    for k, _ in pairs(map) do
        table.insert(ret, k)
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

-- resume_ctx: table {
--     ret: array,
--     deferred: Option<function>
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
                    join_str(join_array({ { name }, opts.args or {} }), " "),
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

        if not array_contains(name, compile_blacklist) then
            if type == "file" then
                table.insert(ret, join_path({ path, name }))
            elseif type == "directory" then
                for _, file in ipairs(list_files_recursively(join_path_dir({ path, name }))) do
                    table.insert(ret, file)
                end
            end
        end
    end

    return ret
end

local function compile(repo_path, compile_path, repos)
    await(spawn("rm", { args = { "-rf", compile_path } }))

    local symlink_table = {}
    local dirs = {} -- directories need to create

    for _, repo_entry in ipairs(repos) do
        local repo = repo_entry.repo
        local fullpath = join_path_dir({ repo_path, repo })
        local repo_files = list_files_recursively(fullpath)

        for _, file in ipairs(repo_files) do
            local relative_path = str_trim_prefix(file, fullpath)

            symlink_table[relative_path] = file -- deduplicating by using relative path as key

            local file_fullpath = join_path({ compile_path, relative_path })
            dirs[dirname(file_fullpath)] = true -- deduplicate
        end
    end

    await(spawn("mkdir", { args = join_array({ { "-p" }, vim.tbl_keys(dirs) }) }))

    for compiled_file_path, srcPath in pairs(symlink_table) do
        local file_fullpath = join_path({ compile_path, compiled_file_path })

        local iserr, err = uv.fs_symlink(srcPath, file_fullpath)
        assert(iserr, err)
    end
end

local function load(repos)
    for _, entry in ipairs(repos) do
        if type(entry) == "table" and entry.fast_setup then
            entry.fast_setup()
        end
    end

    local listen = vim.api.nvim_create_autocmd
    local fire = vim.api.nvim_exec_autocmds

    local function _load()
        vim.schedule(function()
            if vim.v.exiting ~= vim.NIL then
                return
            end
            for _, entry in ipairs(repos) do
                if type(entry) == "table" and entry.setup then
                    entry.setup()
                end
            end
        end)
    end

    local lazyload_pattern = "unnamed_lazyload"

    listen("User", {
        pattern = lazyload_pattern,
        once = true,
        callback = function()
            if vim.v.vim_did_enter == 1 then
                _load()
                return
            end

            listen("UIEnter", {
                once = true,
                callback = _load,
            })
        end,
    })

    fire("User", { pattern = lazyload_pattern, modeline = false })
end

-- table: {
--     workdir: string, used to store cache or maintain compiled artifacts
--     repos: string or table: {
--          repo: string,
--          setup: Option<function>
--     }
-- }
M.setup = function(config)
    assert(config.workdir)
    assert(config.repos)

    local root_path = vim.fn.resolve(config.workdir)
    local repo_path = join_path_dir({ root_path, "repo" })
    local compile_path = join_path_dir({ root_path, "compiled" })
    local compile_after_path = join_path_dir({ compile_path, "after" })

    vim.o.runtimepath = vim.o.runtimepath .. "," .. compile_path .. "," .. compile_after_path

    local repos = config.repos
    local repo_entries = {}

    for _, raw in ipairs(repos) do
        local entry = {}
        local ty = type(raw)

        if ty == "table" then
            entry.repo = raw.repo
            if raw.branch then
                entry.branch = raw.branch
            end
        elseif ty == "string" then
            entry.repo = raw
        else
            error(string.format("repos must be array contains table or string, found '%s'", ty))
        end

        entry.path = join_path_dir({ repo_path, entry.repo })

        table.insert(repo_entries, entry)
    end

    M.config = config
    M.repo_path = repo_path
    M.compile_path = compile_path
    M.compile_after_path = compile_after_path
    M.repo_names = repo_names
    M.repo_entries = repo_entries

    local needs_fetch = {}
    for _, repo in ipairs(repo_entries) do
        local stat = uv.fs_stat(repo.path)
        if stat == nil then
            table.insert(needs_fetch, repo)
        end
    end

    if #needs_fetch > 0 then
        async(function()
            for _, entry in ipairs(needs_fetch) do
                print(string.format("cloning %s", entry.repo))

                local args = {
                    "clone",
                    "--filter=blob:none",
                    "https://github.com/" .. entry.repo,
                    entry.path,
                }
                if entry.branch then
                    array_push(args, "--branch=" .. entry.branch)
                end

                await(spawn("git", { args = args }))
            end

            print("compiling")
            compile(repo_path, compile_path, repo_entries)
            print("compiling done. restart neovim to take effect.")
        end)()
        return
    end

    load(repos)
end

M.update = async(function()
    for _, repo in ipairs(M.repo_entries) do
        print(string.format("updating %s", repo.repo))
        await(spawn("git", { args = { "fetch" }, cwd = repo.path }))
        await(spawn("git", { args = { "checkout", "remotes/origin/HEAD" }, cwd = repo.path }))
    end

    print("compiling")
    compile(M.repo_path, M.compile_path, M.repo_names)
    print("compiling done. restart neovim to take effect.")
end)

return M
