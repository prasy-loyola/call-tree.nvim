local util = vim.lsp.util
local method = "callHierarchy/incomingCalls"
local timeout_ms = 200

local function map_to_item(call_hierarchy_item)
    return {
        filename = assert(vim.uri_to_fname(call_hierarchy_item.uri)),
        text = call_hierarchy_item.name,
        call_hierarchy_item = call_hierarchy_item,
        places = {}
    }
end

local function get_call_locations(call_hierarchy_item, ctx)
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if client then
        local result, err = client.request_sync(method, { item = call_hierarchy_item }, timeout_ms, -1)
        if err then
            vim.notify(err.message, vim.log.levels.WARN)
            return
        end
        if not result then
            return
        end
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


local function show_lines(lines, buf, expand_handler)
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
    local opts = {
        ["relative"] = "editor",
        ["width"] = 100,
        ["height"] = 20,
        ["col"] = 150,
        ["row"] = 2,
        ["anchor"] = "NW",
        ["style"] = "minimal"
    }
    local win = vim.api.nvim_open_win(buf, 0, opts)
    -- optional: change highlight, otherwise Pmenu is used
    vim.api.nvim_set_option_value("winhl", "Normal:MyHighlight", { ["win"] = win })
    vim.keymap.set('n', '<Enter>', function()
        local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
        expand_handler(row)
    end, { buffer = buf })
end

local function get_lines(text)
    local lines = {}
    for s in text:gmatch("[^\r\n]+") do
        table.insert(lines, s)
    end
    return lines
end

local function tree_to_list(tree, list, depth)
    --vim.notify(vim.inspect(tree))
    if not tree then return end
    for _, item in pairs(tree) do
        item.display_text = string.rep("-", depth * 2) .. item.text
        table.insert(list, item)
        tree_to_list(item.incoming, list, depth + 1)
    end
end

local function map_call_tree(call_tree)
    local tree = {}
    tree_to_list(call_tree, tree, 0)
    local lines = {}
    for _, item in pairs(tree) do
        table.insert(lines, item.display_text)
    end

    return tree, lines
end

local M = {}
M.call_tree = nil
M.tree = nil
M.ctx = nil
M.buf = nil

M.expand_function = function(line_num)
    local result = get_call_locations(M.tree[line_num].call_hierarchy_item, M.ctx)
    if result then
        M.tree[line_num].incoming = result
        local tree, lines = map_call_tree(M.call_tree)
        M.tree = tree
        vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, lines)
    end
end


local function display_call_heirarchy(call_tree, ctx)
    local buf = vim.api.nvim_create_buf(false, true)
    M.call_tree = call_tree
    local tree, lines = map_call_tree(M.call_tree)
    M.ctx = ctx
    M.buf = buf
    M.tree = tree
    show_lines(lines, M.buf, M.expand_function)
end


--create function which is to initiate the action
local function get_call_tree()
    local params = util.make_position_params()
    vim.lsp.buf_request(0, "textDocument/prepareCallHierarchy", params,
        function(err, result, ctx)
            if err then
                vim.notify(err.message, vim.log.levels.WARN)
                return
            end
            --TODO: assuming only 1 call heirarchy, need to support for multiple
            if not result then
                return
            end

            local call_hierarchy_item = result[1]
            local items = get_call_locations(call_hierarchy_item, ctx)
            if not items then
                return
            end
            local item = map_to_item(call_hierarchy_item)
            item.incoming = items
            display_call_heirarchy({ item }, ctx)
        end)
end

vim.g.get_call_tree = get_call_tree
vim.api.nvim_set_keymap("", "<leader>R", ":lua vim.g.get_call_tree()<CR>", { noremap = true, silent = true })
