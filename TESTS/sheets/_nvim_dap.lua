-- TESTS/sheets/_nvim_dap.lua -- the setup of the feature sheets (*.sheet.lua). Not a sheet (`testing.sheet` only
-- reads *.sheet.lua); the first step of a sheet runs it with `dofile` (the child's cwd is the project root) and calls
-- what it returns. The directory is in the spec's @cache-inputs.
--
-- dap.nvim is a config layer on top of nvim-dap, which is not a dependency of the suite (TESTS/README.md): the sheets
-- put a stand-in in `package.loaded["dap"]` that holds what dap.nvim writes (adapters, configurations, listeners) and
-- answers `session()`. The debug adapters are "installed by Mason": an empty file in the sandbox's
-- `stdpath("data")/mason/bin` is what `lib.nvim.cross.executable.mason_bin` looks for; nothing ever runs it (nvim-dap,
-- which would, is the stand-in). What dap.nvim itself starts (rustc, zig, ps/tasklist, the companion editor) runs for
-- real.

local BASE = 0x404010

---A table that creates an empty table for every key it is asked for (`dap.listeners.after.event_initialized`).
---@return table
local function autovivify()
  return setmetatable({}, {
    __index = function(t, k)
      local v = {}
      rawset(t, k, v)
      return v
    end,
  })
end

---A debug session over 512 readable bytes at `BASE`, answering `evaluate` and `readMemory` the way GDB's DAP server
---does (TESTS/wkddap/memory/init_spec.lua has the full double); answers come on the next turn of the loop, as a real
---adapter's do.
---@return table
local function memory_session()
  local format = require("wkddap.memory.format")
  local s = {
    capabilities = { supportsReadMemoryRequest = true },
    config = { type = "gdb" },
    current_frame = { id = 7 },
    requests = {},
  }
  function s:request(command, args, cb)
    table.insert(self.requests, command)
    vim.schedule(function()
      if command == "evaluate" then
        if args.expression == "&buffer" then
          cb(nil, { result = "(char (*)[32]) 0x404010 <buffer>", memoryReference = "0x404010" })
        else
          cb({ message = 'No symbol "' .. args.expression .. '" in current context.' }, nil)
        end
      elseif command == "readMemory" then
        local addr = format.parse_address(args.memoryReference) + (args.offset or 0)
        local data = {}
        for i = 0, args.count - 1 do
          local a = addr + i
          data[#data + 1] = (a >= BASE and a < BASE + 512) and (0x41 + a - BASE) % 256 or 0
        end
        cb(
          nil,
          { address = format.hex_address(addr), data = format.encode(data), unreadableBytes = 0 }
        )
      else
        cb({ message = "unsupported: " .. command }, nil)
      end
    end)
  end
  return s
end

---Install the stand-in and the Mason files.
---@param opts? { mason?: string[], session?: "memory" }
---@return table dap the stand-in
return function(opts)
  opts = opts or {}
  local session = opts.session == "memory" and memory_session() or nil
  local noop = function() end
  local dap = {
    adapters = {},
    configurations = {},
    defaults = autovivify(),
    listeners = { after = autovivify(), before = autovivify() },
    repl = { open = noop },
    session = function()
      return session
    end,
  }
  -- Every other function of nvim-dap dap.nvim names (continue, step_over, set_log_level, ...) does nothing here.
  package.loaded["dap"] = setmetatable(dap, {
    __index = function()
      return noop
    end,
  })

  local bin = vim.fn.stdpath("data") .. "/mason/bin"
  vim.fn.mkdir(bin, "p")
  local suffix = vim.fn.has("win32") == 1 and ".cmd" or ""
  for _, name in ipairs(opts.mason or {}) do
    local f = assert(io.open(bin .. "/" .. name .. suffix, "w"))
    f:close()
  end
  return dap
end
