local util = vim.lsp.util
local graph = require('call-tree.graph')

local M = {}

---@class Config
---@field inverted boolean default(true) should tree be inverted
---@field lsp LspConfig

---@class LspConfig
---@field timeout integer default(200ms) timeout for LSP calls

---@class PluginState private object to store plugin state
---@field private id? integer  bufnr of the call tree buffer
---@field private wid? integer window id of the call tree window
---@field private ctx? LspContext
---@field private root? Node
---@field private config? Config
---@field private cur_item? Node
local p = {
  id = nil,
  wid = nil,
  ctx = nil,
  cur_item = nil,
  root = nil,
  config = {
    inverted = true,
    lsp = {
      timeout = 200
    },
  }
}
local incoming_calls_method = "callHierarchy/incomingCalls"

---@class LspContext
---@field client_id integer

---@class Position
---@field line integer
---@field character integer

---@class Range
---@field start Position
---@field end Position

---@class CallHierarchyIncomingCall
---@field from CallHierarchyItem
---@field	fromRanges Range[]

--- Get all incoming call location for a call tree item
---@param item Node
---@param ctx LspContext
---@return nil
local function get_call_locations(item, ctx)
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if client then
    local result, err = client.request_sync(incoming_calls_method, { item = item.item }, p.config.lsp.timeout, -1)
    if err and err.message then
      vim.notify(err.message, vim.log.levels.WARN)
      return
    end
    if not result then return end

    for _, call_hierarchy_call in pairs(result.result) do
      ---@type CallHierarchyItem
      local call_site = call_hierarchy_call["from"]
      item:addIncoming(graph.Node.create(call_site))
    end
    item.probed = true
  else
    vim.notify(
      string.format('Client with id=%d disappeared during call hierarchy request', ctx.client_id),
      vim.log.levels.WARN
    )
    return
  end
end


--- Create a window for the buffer
---@param buf integer buffer number
local function show_window(buf)
  local opts = {
    relative = "editor",
    width = 100,
    height = 20,
    col = vim.api.nvim_win_get_width(0) - 100 - 2,
    row = 2,
    anchor = "NW",
    style = "minimal",
    border = "rounded",
  }
  local win = vim.api.nvim_open_win(buf, 0, opts)
  -- optional: change highlight, otherwise Pmenu is used
  vim.api.nvim_set_option_value("winhl", "Normal:MyHighlight", { ["win"] = win })
  return win
end

--- Find and add the incoming calls for function under cursor and update buffer
---@param item Node current line number in the call tree buffer
local function expand_function(item)
  if not item or item.probed then
    return
  end
  get_call_locations(item, p.ctx)
  local lines = p.root:get_display_rows(true)
  vim.api.nvim_buf_set_lines(p.id, 0, -1, true, lines)
end


local function create_window_with_tree()
  p.id = vim.api.nvim_create_buf(false, true)
  local lines = p.root:get_display_rows(true)
  vim.api.nvim_buf_set_lines(p.id, 0, -1, true, lines)
  p.wid = show_window(p.id)
  vim.keymap.set('n', '<Tab>', function()
    if not p.cur_item.probed then
      expand_function(p.cur_item)
    end
    p.cur_item.expand = not p.cur_item.expand
    local newlines = p.root:get_display_rows(true)
    vim.api.nvim_buf_set_lines(p.id, 0, -1, true, newlines)
  end, { buffer = p.id })

  vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    buffer = p.id,
    callback = function()
      local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
      local item = p.root:get_item_at(row)
      if item then
        p.cur_item:set_focused(false)
        item:set_focused(true)
        p.cur_item = item
        local newlines = p.root:get_display_rows(false)
        vim.api.nvim_buf_set_lines(p.id, 0, -1, true, newlines)
      end
    end
  })
end


--- Show call-tree for the function under cursor
function M.show_call_tree()
  local params = util.make_position_params()
  vim.lsp.buf_request(0, "textDocument/prepareCallHierarchy", params,
    function(err, result, ctx)
      if err then
        vim.notify(err.message, vim.log.levels.WARN)
        return
      end
      if not result then return end

      --TODO: assuming only 1 call heirarchy, need to support for multiple
      ---@type CallHierarchyItem
      local call_hierarchy_item = result[1]
      local item = graph.Node.create(call_hierarchy_item)
      get_call_locations(item, ctx)
      p.ctx = ctx
      p.root = item
      p.cur_item = item
      create_window_with_tree()
    end)
end

--- Setup call-tree plugin
---@param opt Config
function M.setup(opt)
  p.config = vim.tbl_deep_extend("force", p.config or {}, opt or {})
end

return M
