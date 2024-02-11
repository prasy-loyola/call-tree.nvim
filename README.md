# call-tree.nvim
A neovim plugin to display call heirarchy of a function using LSPs already attached to the buffer

## Features
- [x] Display call heirarchy of a function as a tree
- [x] \<Tab\> to expand and collapse tree
- [x] \<Enter\> key to load the file in a different window
- [x] \<Shift-Enter\> key to open the file in a different window and move to that window
- [ ] Telescope integration
- [ ] Show preview of the call location under the cursor


## Install

```lua
{
    'prasy-loyola/call-tree.nvim',
    name = 'call-tree',
    event = 'VeryLazy',
    config = function()
        require'call-tree'.setup()
    end,
    dependencies = {
      {
        's1n7ax/nvim-window-picker',
        name = 'window-picker',
        version = '2.*',
      },
    },

}
```

## References
https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#callHierarchyIncomingCall
