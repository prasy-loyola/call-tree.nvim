local util = vim.lsp.util

local M = {}
local p = { -- private object to store plugin state
  id = nil, -- bufnr of the call tree buffer
  wid = nil, -- window id of the call tree window
  flattened_tree = {}, -- flattened representation of the call tree
  context = nil, -- LSP context
  call_tree = nil, -- current call tree
  config = {
    inverted = true, -- Should the tree be inverted
    lsp = {
      timeout = 200 -- timeout for LSP calls
    }
  }
}
local incoming_calls_method = "callHierarchy/incomingCalls"


--- Map a call tree item to internal representation
-- @param call_hierarchy_item call tree item
local function map_to_item(call_hierarchy_item)
  return {
    filename = assert(vim.uri_to_fname(call_hierarchy_item.uri)),
    text = call_hierarchy_item.name,
    call_hierarchy_item = call_hierarchy_item,
    places = {}
  }
end

--- Get all incoming call location for a call tree item
-- @param call_hierarchy_item call tree item
-- @param ctx LSP context
local function get_call_locations(call_hierarchy_item, ctx)
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if client then
    local result, err = client.request_sync(incoming_calls_method, { item = call_hierarchy_item }, p.config.lsp.timeout, -1)
    if err and err.message then
      vim.notify(err.message, vim.log.levels.WARN)
      return
    end
    if not result then return end

    local items = {}
    for _, call_hierarchy_call in pairs(result.result) do
      call_hierarchy_item = call_hierarchy_call["from"]
      local item = map_to_item(call_hierarchy_item)
      table.insert(items, item)
      for _, range in pairs(call_hierarchy_call.fromRanges) do
        table.insert(item.places, {
          lnum = range.start.line + 1,
          col = range.start.character + 1,
        })
      end
    end
    return items
  else
    vim.notify(
      string.format('Client with id=%d disappeared during call hierarchy request', ctx.client_id),
      vim.log.levels.WARN
    )
  end
end


--- Create a window for the buffer
-- @param buf buffer number
local function show_window(buf)
  local opts = {
    relative = "editor",
    width = 100,
    height = 20,
    col = 150,
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


--- Function to create display text for a call tree item
-- @param depth of this item in the whole call tree
-- @param item call tree item
function p.config.display_text(depth, item)
  local inverted_offset = 0

  if p.config.inverted then
    inverted_offset = 1
  end

  local connector = "╚═"
  if depth < (1 + inverted_offset) then
    connector = ""
  end

  return string.rep(" ", (depth - 1 - inverted_offset) * 2) .. connector .. item.text
end

local function tree_to_list(tree, list, depth)
  if not tree then return depth end
  local max_depth = depth
  for _, item in pairs(tree) do
    if not p.config.inverted then
      item.display_text = p.config.display_text(depth, item)
      table.insert(list, item)
    end
    local inner_depth = tree_to_list(item.incoming, list, depth + 1)
    if inner_depth > max_depth then
      max_depth = inner_depth
    end
    if p.config.inverted then
      item.display_text = p.config.display_text(max_depth - depth, item)
      table.insert(list, item)
    end
  end
  return max_depth
end

--- Map a call tree to a flattened_tree and lines to display in buffer
-- @param call_tree a call tree
local function map_call_tree(call_tree)
  local tree = {}
  tree_to_list(call_tree, tree, 0)
  local lines = {}
  for _, item in pairs(tree) do
    table.insert(lines, item.display_text)
  end

  return tree, lines
end


--- Find and add the incoming calls for function under cursor and update buffer
-- @param line_num current line number in the call tree buffer
local function expand_function(line_num)
  local result = get_call_locations(p.flattened_tree[line_num].call_hierarchy_item, p.ctx)
  if result then
    p.flattened_tree[line_num].incoming = result
    local tree, lines = map_call_tree(p.call_tree)
    p.flattened_tree = tree
    vim.api.nvim_buf_set_lines(p.id, 0, -1, true, lines)
  end
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
      local call_hierarchy_item = result[1]
      local items = get_call_locations(call_hierarchy_item, ctx)
      if not items then
        return
      end
      local item = map_to_item(call_hierarchy_item)
      item.incoming = items
      p.id = vim.api.nvim_create_buf(false, true)
      p.ctx = ctx
      p.call_tree = { item }
      local tree, lines = map_call_tree(p.call_tree)
      p.flattened_tree = tree
      vim.api.nvim_buf_set_lines(p.id, 0, -1, true, lines)
      p.wid = show_window(p.id)
      vim.keymap.set('n', '<Tab>', function()
        local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
        expand_function(row)
      end, { buffer = p.id })
    end)
end

--- Setup call-tree plugin
-- @param opt config
function M.setup(opt)
  p.config = vim.tbl_deep_extend("force", p.config or {}, opt or {})
end

return M
