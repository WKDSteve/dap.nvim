--- The Rust sysroot lookup after a `:cd`: `setup()` registers a DirChanged
--- autocmd that looks up `rustc --print sysroot` for the new directory in the
--- background, at most one lookup per directory, and a session start that
--- races the lookup waits for it inside nvim-dap's coroutine instead of
--- blocking the editor or starting rustc a second time.
---
--- rustc is never run: vim.system is a stand-in whose processes end only when
--- the spec says so, and whose wait() throws -- a session start that blocks
--- the editor fails the case.

describe("wkddap.languages.rust: sysroot lookup after :cd", function()
  local orig_system, orig_notify
  ---@type { argv: string[], cwd: string, on_exit: fun(res: table) }[]
  local procs
  local cwd
  local rustc_present
  ---@type table<string, string>  projects on disk: a and b are Cargo projects, plain is not
  local dirs
  local base

  local function reload()
    package.loaded["wkddap.languages.rust"] = nil
    return require("wkddap.languages.rust")
  end

  --- End process `i` with `sysroot` as its answer.
  ---@param i integer
  ---@param sysroot string
  local function finish(i, sysroot)
    procs[i].on_exit({ code = 0, stdout = sysroot .. "\n", stderr = "" })
  end

  local function dir_changed(dir)
    cwd = dir
    vim.api.nvim_exec_autocmds("DirChanged", { pattern = "global", modeline = false })
  end

  --- Evaluate initCommands the way nvim-dap does: inside a coroutine.
  ---@return fun(): table|nil result  nil while the coroutine is suspended
  local function start_session()
    local result
    local init = package.loaded["dap"].configurations.rust[1].initCommands
    coroutine.wrap(function()
      result = init()
    end)()
    return function()
      return result
    end
  end

  before_each(function()
    orig_system, orig_notify = vim.system, vim.notify
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end
    base = vim.fn.tempname()
    dirs = {}
    for _, name in ipairs({ "a", "b", "plain" }) do
      dirs[name] = base .. "/" .. name
      vim.fn.mkdir(dirs[name] .. "/src", "p")
      if name ~= "plain" then
        vim.fn.writefile({ "[package]" }, dirs[name] .. "/Cargo.toml")
      end
    end
    procs, cwd, rustc_present = {}, dirs.a, true
    package.loaded["dap"] = { adapters = {}, configurations = {} }
    package.loaded["wkddap.config"] = {
      get_adapter_path = function(_)
        return "codelldb"
      end,
    }
    package.loaded["wkddap.utils.executable"] = {
      exists = function(_)
        return rustc_present
      end,
    }
    package.loaded["wkddap.utils.paths"] = {
      workspace_root = function()
        return cwd
      end,
      normalize = function(p)
        return p
      end,
      join = function(...)
        return table.concat({ ... }, "/")
      end,
    }
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(argv, opts, on_exit)
      procs[#procs + 1] = { argv = argv, cwd = opts.cwd, on_exit = on_exit }
      return {
        wait = function()
          error("the editor waited for rustc", 0)
        end,
      }
    end
  end)

  after_each(function()
    vim.system, vim.notify = orig_system, orig_notify
    pcall(vim.api.nvim_del_augroup_by_name, "WkdDapRustSysroot")
    package.loaded["dap"] = nil
    package.loaded["wkddap.config"] = nil
    package.loaded["wkddap.utils.executable"] = nil
    package.loaded["wkddap.utils.paths"] = nil
    package.loaded["wkddap.languages.rust"] = nil
    vim.fn.delete(base, "rf")
  end)

  it("looks up the sysroot of the new directory in the background after a :cd", function()
    local rust = reload()
    assert.is_true(rust.setup())
    assert.are.equal(1, #procs, "setup looks up the directory it ran in")

    dir_changed(dirs.b .. "/src")
    assert.are.equal(2, #procs, "the :cd starts a lookup for the new directory")
    assert.are.same({ "rustc", "--print", "sysroot" }, procs[2].argv)
    assert.are.equal(dirs.b .. "/src", procs[2].cwd)
    assert.is_false(rust.sysroot_settled())

    finish(1, "/toolchains/a")
    finish(2, "/toolchains/b")
    assert.is_true(rust.sysroot_settled())
  end)

  it("starts nothing after a :cd when rustc is not installed", function()
    rustc_present = false
    local rust = reload()
    rust.setup()
    dir_changed(dirs.b)
    assert.are.equal(0, #procs)
  end)

  it("starts nothing after a :cd into a directory outside any Cargo project", function()
    local rust = reload()
    rust.setup()
    dir_changed(dirs.plain)
    assert.are.equal(1, #procs, "only the lookup of setup()")
  end)

  it("starts no second lookup for the same directory", function()
    local rust = reload()
    rust.setup()
    dir_changed(dirs.a)
    assert.are.equal(1, #procs, "a lookup for this directory is already running")

    finish(1, "/toolchains/a")
    dir_changed(dirs.a)
    assert.are.equal(1, #procs, "the answer for this directory is cached")
  end)

  it("a session racing the lookup waits for it without blocking or starting rustc again", function()
    local rust = reload()
    rust.setup()
    rust.load()
    dir_changed(dirs.b)
    assert.are.equal(2, #procs)

    local result = start_session()
    assert.is_nil(result(), "the session waits for the running lookup")
    assert.are.equal(2, #procs, "it joins the running lookup")

    finish(2, "/toolchains/b")
    assert.is_true(vim.wait(1000, function()
      return result() ~= nil
    end, 5))
    assert.are.equal(
      'command script import "/toolchains/b/lib/rustlib/etc/lldb_lookup.py"',
      result()[1]
    )
    finish(1, "/toolchains/a")
  end)

  it("a session in a directory nobody looked up yet asks rustc without blocking", function()
    local rust = reload()
    rust.load()
    cwd = dirs.plain -- not a Cargo project: no lookup before the session
    local result = start_session()
    assert.are.equal(1, #procs)
    assert.are.equal(dirs.plain, procs[1].cwd)
    assert.is_nil(result())

    finish(1, "/toolchains/c")
    assert.is_true(vim.wait(1000, function()
      return result() ~= nil
    end, 5))
    assert.truthy(result()[1]:find("/toolchains/c/", 1, true))
  end)
end)
