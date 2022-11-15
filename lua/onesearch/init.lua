local M = {}
local api = vim.api
local uv = vim.loop


function M.setup(user_conf)
    M.conf = vim.tbl_deep_extend("force", M.conf, user_conf)
end

M.conf = {
    flash_t = 200,
    hl = {
        overlay = "NonText",
        multi = "OnesearchMulti",
        single = "OnesearchSingle",
        select = "WarningMsg",
        flash = "Search",
    },
    hints = { "a", "s", "d", "f", "h", "j", "k", "l", "w", "e", "r", "u", "i", "o", "x", "c", "n", "m" }
}

M.hint_ns = vim.api.nvim_create_namespace("OnesearchHints")
M.background_ns = vim.api.nvim_create_namespace("OnesearchBackground")
M.flash_ns = vim.api.nvim_create_namespace("OnesearchFlash")
vim.api.nvim_set_hl(0, 'OnesearchMulti', { fg = "#7fef00", bold = true })
vim.api.nvim_set_hl(0, 'OnesearchSingle', { fg = "#66ccff", bold = true })

-- from :help uv.new_timer()
function SetTimeout(timeout, callback)
    local timer = uv.new_timer()
    timer:start(timeout, 0, function()
        timer:stop()
        timer:close()
        callback()
    end)
    return timer
end

-- is this seriously not a default string method?
function M.lpad(str, len, char)
    return str .. string.rep(char or " ", len - #str)
end

function M.flash(lnum)
    -- I sometimes mistype the jump location and I have then to look for
    -- where my cursor went. I'm gonna make the landing line flash to
    -- help me find it more easily.
    local winwidth = vim.fn.winwidth(0)
    local line = vim.fn.getline(lnum)
    local mask = M.lpad(line, winwidth, " ")
    local flash_id = api.nvim_buf_set_extmark(0, M.flash_ns, lnum - 1, 0, {
        virt_text = { { mask, M.conf.hl.flash } },
        virt_text_pos = "overlay",
    })
    SetTimeout(
        M.conf.flash_t,
        vim.schedule_wrap(function()
            api.nvim_buf_del_extmark(0, M.flash_ns, flash_id)
        end))
end

function M.visible_lines()
    local top = vim.fn.line("w0")
    local bot = vim.fn.line("w$")
    return { top = top, bot = bot }
end

function M.search_pos(pattern, mode)
    -- NOTE: moves cursor to match! need to save/restore
    local res
    if mode then
        res = vim.fn.searchpos(pattern, mode)
    else
        res = vim.fn.searchpos(pattern)
    end
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

function M.visible_matches(str)
    -- there are 4 options
    --   1. some matches are visible :  #matches >  0 , next != nil
    --   2.   no matches are visible :  #mathces == 0 , next != nil
    --   3.  all matches are visible :  #matches >  0 , next == nil
    --   4.   no matches             :  #matches == 0 , next == nil

    local save_cursor = api.nvim_win_get_cursor(0) -- save location

    local visible = M.visible_lines()

    -- hide highlights, make everything grey.
    for lnum = visible.top - 1, visible.bot - 1 do
        vim.api.nvim_buf_add_highlight(0, M.background_ns, M.conf.hl.overlay, lnum, 0, -1)
    end

    local matches = {}
    local seen = M.newAutotable(2);

    -- Start searching from first visible line
    vim.fn.cursor({ visible.top, 1 })

    -- Storytime: the search() function in vim doesn't accept matches AT
    -- the cursor position. So when I move to the beginning of the visible
    -- range I won't detect matches that are right at the beginning.
    -- The flag "c" lets you accept matches AT cursor position, but that means
    -- that the cursor doesn't move to new matches.
    -- To avoid getting stuck in place I only use "c" on the first search

    local res = M.search_pos(str, "c")
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
    local matches, _ = M.visible_matches(pat)
    local color = (#matches == 1) and "OnesearchSingle" or "OnesearchMulti"
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
        matches, next = M.visible_matches(pat)
        color = (#matches == 1) and "OnesearchSingle" or "OnesearchMulti"

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
                if i < #M.conf.hints then
                    local c = M.conf.hints[i]
                    targets[c] = match
                    api.nvim_buf_set_extmark(0, M.hint_ns, match.line - 1, match.col - 1, {
                        virt_text = { { c, M.conf.hl.select } },
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
                if M.conf.flash_t > 0 then
                    M.flash(selected.line)
                end
            end
        else
            local match = matches[1]
            api.nvim_win_set_cursor(0, { match.line, match.col - 1 })
            if M.conf.flash_t > 0 then
                M.flash(match.line)
            end
        end
    end

    -- Remove extmarks and restore highlighting
    M.clear()
    vim.cmd('redraw')
end

function M.clear()
    api.nvim_buf_clear_namespace(0, M.hint_ns, 0, -1)
    api.nvim_buf_clear_namespace(0, M.background_ns, 0, -1)
    -- api.nvim_buf_clear_namespace(0, M.flash_ns, 0, -1)
end

return M
