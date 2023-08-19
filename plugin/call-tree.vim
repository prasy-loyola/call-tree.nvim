"make sure plugin is loaded only once
if exists("g:loaded_call_tree_nvim")
    finish
endif
let g:loaded_call_tree_nvim = 1

" Exposes the plugin's functions for use as commands in Neovim.
command! -nargs=0 CallTreeShow lua require("call-tree").show_call_tree()
