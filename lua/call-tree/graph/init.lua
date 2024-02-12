local M = {}

---@class CallHierarchyItem
---@field name string
---@field uri string
---@field kind unknown SymbolKind
---@field tags? unknown SymbolTag[]
---@field detail? string
---@field range Range
---@field selectionRange Range
---@field data? unknown

---@class Node
---@field name string
---@field private incoming Node[]
---@field expand boolean
---@field parent Node
---@field focused boolean
---@field filename string
---@field item  CallHierarchyItem,
---@field private flattened Node[]
---@field depth integer
---@field probed boolean
---@field ctx LspContext
---@field notes string
Node = {}
Node.__index = Node

---Create a new Node
---@param item CallHierarchyItem
---@param ctx LspContext
---@return Node
function Node.create(item, ctx)
  local self = setmetatable({
    name = item.name,
    item = item,
    filename = assert(vim.uri_to_fname(item.uri)),
    incoming = {},
    expand = false,
    flattened = {},
    depth = 0,
    ctx = ctx,
    notes = "",
  }, Node)
  return self
end




function Node:set_depth(depth)
  self.depth = depth
  if self.incoming == nil then
    return
  end

  for _, v in ipairs(self.incoming) do
    v:set_depth(depth+1)
  end
end

---@param node Node
function Node:add_incoming(node)
  node:set_depth(self.depth+1)
  table.insert(self.incoming, node)
  node.parent = self
end

---@param node Node
function Node:remove_incoming(node)
  for i = 1, #self.incoming do
    if self.incoming[i] == node then
      table.remove(self.incoming, i)
      return
    end
  end
end

---@param level integer
function Node:display(level)
  if not self.expand then
    return
  end
  local indent = ""
  local char = self.focused and "-" or " "
  for _ = 0, level do
    indent = indent .. char
  end
  for _, v in ipairs(self.incoming) do
    v:display(level + 1)
  end
end

---@param focused boolean
function Node:set_focused(focused)
  if self.focused == focused then
    return
  end
  self.focused = focused
  if self.parent ~= nil then
    self.parent:set_focused(focused)
  end
end

---@return Node[]
function Node:flatten()
  self.flattened = {}
  table.insert(self.flattened, self)
  if not self.expand then
    return self.flattened
  end
  for _, n in ipairs(self.incoming) do
    for _, cn in ipairs(n:flatten()) do
      table.insert(self.flattened, cn)
    end
  end
  return self.flattened
end


---@class HighlightGroups
---@field line integer
---@field indent integer
---@field name integer
---@field notes integer
---@field detail integer

---@param refresh boolean
function Node:get_display_rows(refresh)
  local nodes = refresh and self:flatten() or self.flattened
  local text = {}
  ---@type HighlightGroups[]
  local higroups = {}
  local last_focused = 0

  -- find the line with the last focused item
  local last_focused_line = 1
  for i = #nodes, 1, -1 do
    if nodes[i].focused then
      last_focused_line = i
      break
    end
  end

  for r, n in ipairs(nodes) do
    local indent = ""
    if n.focused then
      last_focused = n.depth
    end
    for i = 0, n.depth + 1 do
      if n.focused then
        if i == last_focused and last_focused > 0 then
          indent = indent .. "╰"
        elseif i > last_focused then
          indent = indent .. "─"
        else
          indent = indent .. " "
        end
      else
        if r < last_focused_line and i - 1 == last_focused then
          indent = indent .. "│"
        else
          indent = indent .. " "
        end
      end
    end
    if n.expand then
      indent = indent .. "▼"
    else
      indent = indent .. "▶"
    end
    table.insert(text, indent .. n.name .. " " .. n.notes .. n.item.detail)
    table.insert(higroups, {line = r, indent = #indent, name=#n.name+1, notes=#n.notes, detail=#n.item.detail})
  end
  return text, higroups
end

---@param notes string
function Node:add_notes(notes)
  self.notes = notes
end

---@return Node?
function Node:get_item_at(index)
  if #self.flattened < index then
    return nil
  end
  return self.flattened[index]
end

M.Node = Node
return M
