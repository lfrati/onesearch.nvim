local M = {}
local api = vim.api

M.hint_ns = vim.api.nvim_create_namespace("SeacherHints")
M.background_ns = vim.api.nvim_create_namespace("SeacherBackground")
M.hl = {
    overlay = "NonText",
    multi = "SearcherMulti",
    single = "SearcherSingle",
    select = "WarningMsg",
}
M.hints = { "a", "s", "d", "f", "h", "j", "k", "l", "w", "e", "r", "u", "i", "o", "x", "c", "n", "m" }
vim.api.nvim_set_hl(0, 'SearcherMulti', { fg = "#7fef00", bold = true })
vim.api.nvim_set_hl(0, 'SearcherSingle', { fg = "#66ccff", bold = true })

function M.visible_lines()
    local top = vim.fn.line("w0")
    local bot = vim.fn.line("w$")
    return { top = top, bot = bot }
end

function M.search_pos(pattern)
    -- NOTE: moves cursor to match! need to save/restore
    local res = vim.fn.searchpos(pattern)
    return { line = res[1], col = res[2] }
end

function M.newAutotable(dim)
    -- https://stackoverflow.com/a/21287623
    -- I need to check I'm not going over the same match multiple times
    -- so I'll use some metatable magic to make a pair -> seen mapping
    local MT = {};
    for i = 1, dim do
        MT[i] = { __index = function(t, k)
            if i < dim then
                t[k] = setmetatable({}, MT[i + 1])
                return t[k];
            end
        end }
    end
    return setmetatable({}, MT[1]);
end

function M.matches_within(str)
    -- there are 4 options
    --   1. some matches are visible :  #matches >  0 , next != nil
    --   2. no matches are visible   :  #mathces == 0 , next != nil
    --   3. all matches are visible  :  #matches >  0 , next == nil
    --   4. no matches               :  #matches == 0 , next == nil

    local save_cursor = api.nvim_win_get_cursor(0) -- save location

    local visible = M.visible_lines()

    -- hide highlights, make everything grey.
    for lnum = visible.top - 1, visible.bot - 1 do
        vim.api.nvim_buf_add_highlight(0, M.background_ns, M.hl.overlay, lnum, 0, -1)
    end

    local matches = {}
    local seen = M.newAutotable(2);

    -- Start searching from first visible line
    vim.fn.cursor({ visible.top, 1 }) -- cursor is 1-indexed
    local res = M.search_pos(str) -- forward search, wrapping
    while (res.line > 0 --[[ matches found ]]
        and res.line >= visible.top --[[ match is visible ]]
        and res.line <= visible.bot --[[ match is visible ]]
        and seen[res.line][res.col] == nil--[[ new match ]]
        ) do
        seen[res.line][res.col] = true
        table.insert(matches, res)
        res = M.search_pos(str)
    end

    api.nvim_win_set_cursor(0, save_cursor) -- restore location
    return matches, res.col > 0 and res or nil
end

function M.getkey()
    local ok, key = pcall(vim.fn.getchar)
    if not ok then -- Interrupted by <C-c>
        -- TODO: How do I deal with these errors?
        return nil
    end

    if type(key) == 'number' then
        key = vim.fn.nr2char(key)
    end
    return key
end

function M.show(matches, pat, color)
    for _, match in ipairs(matches) do
        api.nvim_buf_set_extmark(0, M.hint_ns, match.line - 1, match.col - 1, {
            virt_text = { { pat, color } },
            virt_text_pos = "overlay"
        })
    end
end

function M.match_and_show(pat)
    api.nvim_buf_clear_namespace(0, M.hint_ns, 0, -1)
    local matches, _ = M.matches_within(pat)
    local color = (#matches == 1) and "SearcherSingle" or "SearcherMulti"
    M.show(matches, pat, color)
end

-- from  https://github.com/phaazon/hop.nvim/blob/baa92e09ea2d3085bdf23c00ab378c1f27069f6f/lua/hop/init.lua#L198
function M.search()
    local prompt = "Search: "
    local K_Esc = api.nvim_replace_termcodes('<Esc>', true, false, true) -- you know who I am
    local K_BS = api.nvim_replace_termcodes('<BS>', true, false, true) -- normal delete
    local K_CR = api.nvim_replace_termcodes('<CR>', true, false, true) -- enter
    local K_TAB = api.nvim_replace_termcodes('<Tab>', true, false, true)
    local pat_keys = {}
    local pat = ''

    -- TODO: Do I need/want to deal with this stuff?
    -- local K_C_H = api.nvim_replace_termcodes('<C-H>', true, false, true) -- weird delete?
    -- local K_NL = api.nvim_replace_termcodes('<NL>', true, false, true) -- <C-J>? dafuq?

    local save_cursor = api.nvim_win_get_cursor(0) -- save location

    local next = nil
    local accepted = false
    local matches, key, color

    while (true) do
        vim.cmd('redraw')
        api.nvim_echo({ { prompt, 'Question' }, { pat } }, false, {})

        key = M.getkey()

        if key == K_Esc then -- reject
            api.nvim_win_set_cursor(0, save_cursor)
            break
        elseif key == K_CR then
            accepted = true
            break -- accept
        elseif key == K_TAB then -- next
            if next then
                api.nvim_win_set_cursor(0, { next.line, next.col })
                api.nvim_exec("normal! zt", false)
            end
        elseif key == K_BS then -- decrease
            pat_keys[#pat_keys] = nil
        else -- increase
            pat_keys[#pat_keys + 1] = key
        end

        pat = vim.fn.join(pat_keys, '')

        -- delete stale extmarks before drawing new ones
        api.nvim_buf_clear_namespace(0, M.hint_ns, 0, -1)
        matches, next = M.matches_within(pat)
        color = (#matches == 1) and "SearcherSingle" or "SearcherMulti"

        if #matches > 0 then
            M.show(matches, pat, color)
        else
            -- if there are matches somewhere else move there
            if next then
                api.nvim_win_set_cursor(0, { next.line, next.col - 1 })
                -- since I know there was a match I need to update the highlight
                M.match_and_show(pat)
            end
        end
    end

    if accepted then
        local targets = {}

        if #matches > 1 then
            -- remove neon green hints to better see targets
            api.nvim_buf_clear_namespace(0, M.hint_ns, 0, -1)
            for i, match in ipairs(matches) do
                if i < #M.hints then
                    local c = M.hints[i]
                    targets[c] = match
                    api.nvim_buf_set_extmark(0, M.hint_ns, match.line - 1, match.col - 1, {
                        virt_text = { { c, M.hl.select } },
                        virt_text_pos = "overlay"
                    })
                end
            end

            -- make sure to show the new hints
            vim.cmd('redraw')

            key = M.getkey()
            local selected = targets[key]
            if selected then
                api.nvim_win_set_cursor(0, { selected.line, selected.col - 1 })
            end
        else
            local match = matches[1]
            api.nvim_win_set_cursor(0, { match.line, match.col - 1 })
        end
    end

    -- Remove extmarks and restore highlighting
    M.clear()
    vim.cmd('redraw')
end

function M.clear()
    api.nvim_buf_clear_namespace(0, M.hint_ns, 0, -1)
    api.nvim_buf_clear_namespace(0, M.background_ns, 0, -1)
end

-- xenomorph

return M
