local M = {}

function M.setup()

    local core = require("onesearch.core")
    core.hint_ns = vim.api.nvim_create_namespace("SeacherHints")
    core.background_ns = vim.api.nvim_create_namespace("SeacherBackground")
    core.hl = {
        overlay = "NonText",
        multi = "SearcherMulti",
        single = "SearcherSingle",
        select = "WarningMsg",
    }
    core.hints = { "l", "a", "k", "s", "j", "d", "o", "w", "e", "p" }

    vim.api.nvim_set_hl(0, 'SearcherMulti', { fg = "#7fef00", bold = true })
    vim.api.nvim_set_hl(0, 'SearcherSingle', { fg = "#66ccff", bold = true })
    vim.keymap.set("n", "<leader>/", ":lua require('onesearch.core').prompt()<CR>")

end

return M
