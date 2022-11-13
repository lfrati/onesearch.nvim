print("Loaded searcher")

vim.keymap.set("n", "<leader><leader>r", ":lua R('searcher.search').prompt()<CR>")
vim.keymap.set("n", "<leader><leader>t", ":lua R('searcher.search').matches_within('local')<CR>")

vim.api.nvim_set_hl(0, 'SearcherMulti', { fg = "#7fef00", bold = true })
vim.api.nvim_set_hl(0, 'SearcherSingle', { fg = "#e0162b", bold = true })
R("searcher.search").clear()
