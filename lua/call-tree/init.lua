local util = vim.lsp.util
local picker = require('window-picker')
local graph = require('call-tree.graph')
picker.setup()

local M = {}

---@class Config
---@field lsp LspConfig

---@class LspConfig
---@field timeout integer default(200ms) timeout for LSP calls

---@class PluginState private object to store plugin state
---@field private bufnr? integer  bufnr of the call tree buffer
---@field private wid? integer window id of the call tree window
---@field private ctx? LspContext
---@field private root? Node
---@field private config? Config
---@field private cur_item? Node
---@field private copied_item? Node
local P = {
  bufnr = nil,
  wid = nil,
  ctx = nil,
  cur_item = nil,
  root = nil,
  config = {
    lsp = {
      timeout = 200
    },
  },
  copied_item = nil,
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
    local result, err = client.request_sync(incoming_calls_method, { item = item.item }, P.config.lsp.timeout, -1)
    if err and err.message then
      vim.notify(err.message, vim.log.levels.WARN)
      return
    end
    if not (result and result.result) then return end

    for _, call_hierarchy_call in pairs(result.result) do
      ---@type CallHierarchyItem
      local call_site = call_hierarchy_call["from"]
      item:add_incoming(graph.Node.create(call_site, ctx))
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
  local win = vim.api.nvim_open_win(buf, true, opts)
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
  get_call_locations(item, P.ctx)
  M.refresh()
end

local function handle_expand()
  if not P.cur_item.probed then
    expand_function(P.cur_item)
  end
  P.cur_item.expand = not P.cur_item.expand
  M.refresh()
end

local function handle_open()
  P.cur_item.expand = not P.cur_item.expand
  local wid = picker.pick_window()
  vim.api.nvim_set_current_win(wid)
  vim.cmd.edit(P.cur_item.filename)
  local start = P.cur_item.item.range.start;
  vim.api.nvim_win_set_cursor(wid, { start.line + 1, start.character })
  vim.cmd.norm('zz')
end

local function handle_cursor_move()
  local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
  local item = P.root:get_item_at(row)
  if item then
    P.cur_item:set_focused(false)
    item:set_focused(true)
    P.cur_item = item
    local newlines = P.root:get_display_rows(false)
    vim.api.nvim_buf_set_lines(P.bufnr, 0, -1, true, newlines)
  end
end

function M.insert_up()
  if P.cur_item == nil or P.copied_item == nil then
    return
  end
  M.insert_between_parent(P.cur_item, P.copied_item)
  P.copied_item.expand = true
  P.copied_item = nil
  M.refresh()
end

function M.insert_down()
  if P.cur_item == nil or P.copied_item == nil then
    return
  end
  P.cur_item:add_incoming(P.copied_item)
  P.cur_item.expand = true
  P.copied_item = nil
  M.refresh()
end

function M.remove_current()
  P.copied_item = P.cur_item
  if P.cur_item.parent ~= nil then
    P.cur_item.parent:remove_incoming(P.cur_item)
  end
  M.refresh()
end


function M.refresh()
  local newlines = P.root:get_display_rows(true)
  vim.api.nvim_buf_set_lines(P.bufnr, 0, -1, true, newlines)
end

local function create_window_with_tree()
  P.bufnr = vim.api.nvim_create_buf(false, true)
  M.refresh()
  P.wid = show_window(P.bufnr)
  vim.keymap.set('n', '<Tab>', handle_expand, { buffer = P.bufnr })
  vim.keymap.set('n', '<S-CR>', handle_open, { buffer = P.bufnr })
  vim.keymap.set('n', 'dd', M.remove_current, { buffer = P.bufnr })
  vim.keymap.set('n', 'P', M.insert_up, { buffer = P.bufnr })
  vim.keymap.set('n', 'p', M.insert_down, { buffer = P.bufnr })
  vim.keymap.set('n', '<CR>', function()
    handle_open()
    vim.api.nvim_set_current_win(P.wid)
  end, { buffer = P.bufnr })

  vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    buffer = P.bufnr,
    callback = handle_cursor_move
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
      local item = graph.Node.create(call_hierarchy_item, ctx)
      get_call_locations(item, ctx)
      P.ctx = ctx
      P.root = item
      P.cur_item = item
      create_window_with_tree()
    end)
end

--- Copy the function under cursor, which can then be inserted in the call heirarchy
function M.copy_function()
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
      local item = graph.Node.create(call_hierarchy_item, ctx)
      P.copied_item = item
    end)
end

--- Insert the copied function between the current call function and its parent
---@param cur_item Node
---@param item Node
function M.insert_between_parent(cur_item, item)
  local parent = cur_item.parent

  if parent ~= nil then
    parent:remove_incoming(cur_item)
    parent:add_incoming(item)
  else
    P.root = item
  end
  item:add_incoming(P.cur_item)
end

--- Setup call-tree plugin
---@param opt Config
function M.setup(opt)
  P.config = vim.tbl_deep_extend("force", P.config or {}, opt or {})
end

return M
