---@module 'wkddap.languages.rust'
--- Rust: adapter (CodeLLDB) + launch configurations (with rustc
--- pretty-printer setup)

local config = require("wkddap.config")
local paths = require("wkddap.utils.paths")
local executable = require("wkddap.utils.executable")
local notify = require("wkddap.utils.notify")

local M = {}

---@internal
---`rustc --print sysroot`, keyed by the directory it ran in. Not one value
---per session: a `rust-toolchain.toml` or `rustup override` makes the answer
---depend on the working directory, so a `:cd` into another project must not
---keep serving the first project's toolchain. Only successful lookups are
---stored -- a missing or failing rustc is re-checked at the next session
---start instead of being remembered as an empty sysroot.
---@type table<string, string>
local sysroot_cache = {}

---@internal
---Store a successful lookup for `cwd`; a failure or empty answer stores nothing.
---@param cwd string
---@param res { code: integer, stdout: string|nil }
---@return nil
local function remember_sysroot(cwd, res)
  -- vim.trim, not vim.fn.trim: this also runs from a vim.system callback,
  -- a fast-event context where Vimscript functions raise E5560.
  local sysroot = res.code == 0 and res.stdout and vim.trim(res.stdout) or ""
  if sysroot ~= "" then
    sysroot_cache[cwd] = sysroot
  end
end

---@internal
---Backstop for a rustup proxy that hangs (e.g. resolving a toolchain): the
---lookup ends, its waiters get their answer (no sysroot) and the session starts.
local SYSROOT_TIMEOUT_MS = 30000

---@internal
---@class wkddap.RustSysrootLookup
---@field proc vim.SystemObj|nil  nil until vim.system returned
---@field waiters fun()[]

---@internal
---The lookup running per directory: at most one `rustc --print sysroot` per
---cwd at a time. A prefetch, a second `:cd` into the same project and a
---session start racing the prefetch all share it instead of starting rustc
---again.
---@type table<string, wkddap.RustSysrootLookup>
local inflight = {}

---@internal
---Start the lookup for `cwd`, or join the one already running.
---
---`on_done` (optional) runs on the main loop once the lookup ended, whatever
---its outcome; it is never called before this function returned, and never
---when this function returns nil.
---@param cwd string
---@param on_done? fun()
---@return wkddap.RustSysrootLookup|nil lookup  nil when rustc could not be started
local function lookup_sysroot(cwd, on_done)
  local running = inflight[cwd]
  if running then
    running.waiters[#running.waiters + 1] = on_done
    return running
  end
  ---@type wkddap.RustSysrootLookup
  local lookup = { waiters = { on_done } }
  inflight[cwd] = lookup
  local ok, proc = pcall(
    vim.system,
    { "rustc", "--print", "sysroot" },
    { text = true, cwd = cwd, timeout = SYSROOT_TIMEOUT_MS },
    function(res)
      remember_sysroot(cwd, res)
      -- Cleared before the waiters run, so one of them may look up again.
      if inflight[cwd] == lookup then
        inflight[cwd] = nil
      end
      for _, waiter in ipairs(lookup.waiters) do
        -- One schedule per waiter: a waiter that throws does not cost the
        -- others their answer.
        vim.schedule(waiter)
      end
    end
  )
  if not ok then
    -- Nobody else can have joined yet; the caller learns it from the nil.
    inflight[cwd] = nil
    return nil
  end
  lookup.proc = proc
  return lookup
end

---@internal
---Warm the cache for the current directory in the background.
---
---`initCommands` below needs the sysroot to point LLDB at Rust's
---pretty-printers. Prefetching it when the language module loads, and again
---after every `:cd` (see M.setup), means the value is virtually always there by
---the time a session actually starts; the session start only waits for the
---race where it is not.
---@return nil
local function prefetch_sysroot()
  local cwd = paths.workspace_root()
  if sysroot_cache[cwd] or inflight[cwd] or not executable.exists("rustc") then
    return
  end
  lookup_sysroot(cwd)
end

---@internal
---@return string|nil sysroot  nil when rustc is unavailable or gave no answer
local function rustc_sysroot()
  local cwd = paths.workspace_root()
  if sysroot_cache[cwd] then
    return sysroot_cache[cwd]
  end
  if not inflight[cwd] and not executable.exists("rustc") then
    return nil
  end
  -- The prefetch has not landed yet. nvim-dap evaluates a configuration's
  -- function options inside its own coroutine: wait there without blocking
  -- the editor.
  local co, is_main = coroutine.running()
  if co and not is_main then
    if
      lookup_sysroot(cwd, function()
        local ok, err = coroutine.resume(co)
        if not ok then
          error(err, 0)
        end
      end)
    then
      coroutine.yield()
    end
    return sysroot_cache[cwd]
  end
  -- Called outside a coroutine (not by nvim-dap): join the running lookup
  -- rather than starting a second rustc, and wait for it.
  local lookup = lookup_sysroot(cwd)
  if lookup and lookup.proc then
    lookup.proc:wait()
  end
  return sysroot_cache[cwd]
end

---@internal
---Whether no sysroot lookup is running (a seam for specs and sheets).
---@return boolean
function M.sysroot_settled()
  return next(inflight) == nil
end

---@return boolean success
function M.setup()
  local ok_dap, dap = pcall(require, "dap")
  if not ok_dap then
    return false
  end

  local adapter_path = config.get_adapter_path("rust")
  if not adapter_path then
    return false
  end

  dap.adapters.codelldb = dap.adapters.codelldb
    or {
      type = "server",
      port = "${port}",
      executable = {
        command = adapter_path,
        args = { "--port", "${port}" },
      },
    }

  prefetch_sysroot()
  -- The cache is per directory: after a `:cd` into another project the first
  -- session there would otherwise have to wait for rustc. Registering the
  -- autocmd starts nothing; the lookup runs when the directory changes.
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("WkdDapRustSysroot", { clear = true }),
    desc = "Look up rustc's sysroot for the new directory in the background",
    callback = function()
      prefetch_sysroot()
    end,
  })

  return true
end

---@return boolean success
function M.load()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return false
  end

  dap.configurations.rust = {
    {
      name = "Launch",
      type = "codelldb",
      request = "launch",
      -- Async prompt via nvim-dap's coroutine.wrap() config resolution; see
      -- docs/FEATURES/LANGUAGES.md.
      program = function()
        local co = assert(coroutine.running(), "program() must run inside a coroutine")
        require("ui.kit").input({
          title = "Path to executable: ",
          default = paths.join(vim.fn.getcwd(), "target", "debug", ""),
          completion = "file",
          on_submit = function(input)
            coroutine.resume(co, input)
          end,
          on_cancel = function()
            coroutine.resume(co, "")
          end,
        })
        return paths.normalize(coroutine.yield())
      end,
      cwd = "${workspaceFolder}",
      stopOnEntry = false,
      initCommands = function()
        local sysroot = rustc_sysroot()
        if not sysroot then
          -- No toolchain to borrow the pretty-printers from. Plain LLDB
          -- output beats an import error for a path rooted at "/" whose
          -- text never mentions the actual cause.
          notify.warn("rustc not found -- starting without Rust's LLDB pretty-printers")
          return {}
        end
        local script_import = 'command script import "'
          .. sysroot
          .. '/lib/rustlib/etc/lldb_lookup.py"'
        local commands_file = sysroot .. "/lib/rustlib/etc/lldb_commands"
        local commands = {}
        local file = io.open(commands_file, "r")
        if file then
          for line in file:lines() do
            table.insert(commands, line)
          end
          file:close()
        end
        table.insert(commands, 1, script_import)
        return commands
      end,
    },
  }

  return true
end

return M
