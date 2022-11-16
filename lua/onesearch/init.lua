local M = {}

--------------------------------------------------------------------------------
-- CONF
--------------------------------------------------------------------------------

local api = vim.api
local uv = vim.loop

local hint_ns = vim.api.nvim_create_namespace("OnesearchHints")
local background_ns = vim.api.nvim_create_namespace("OnesearchBackground")
local flash_ns = vim.api.nvim_create_namespace("OnesearchFlash")
vim.api.nvim_set_hl(0, 'OnesearchMulti', { fg = "#7fef00", bold = true })
vim.api.nvim_set_hl(0, 'OnesearchSingle', { fg = "#66ccff", bold = true })

--------------------------------------------------------------------------------
-- UTILS
--------------------------------------------------------------------------------

-- from :help uv.new_timer()
local function set_timeout(timeout, callback)
    local timer = uv.new_timer()
    timer:start(timeout, 0, function()
        timer:stop()
        timer:close()
        callback()
    end)
    return timer
end

-- is this seriously not a default string method?
local function lpad(str, len, char)
    return str .. string.rep(char or " ", len - #str)
end

local function get_whole_line(lnum)
    local winwidth = vim.fn.winwidth(0)
    local line = vim.fn.getline(lnum)
    local mask = lpad(line, winwidth, " ")
    return mask
end

local function visible_lines()
    return {
        top = vim.fn.line("w0"),
        bot = vim.fn.line("w$")
    }
end

local function new_autotable(dim)
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

--------------------------------------------------------------------------------
-- LOCAL STUFF
--------------------------------------------------------------------------------

local function flash_line(lnum)
    -- I sometimes mistype the jump location and I have then to look for
    -- where my cursor went. I'm gonna make the landing line flash to
    -- help me find it more easily.
    local mask = get_whole_line(lnum)
    local flash_id = api.nvim_buf_set_extmark(0, flash_ns, lnum - 1, 0, {
        virt_text = { { mask, M.conf.hl.flash } },
        virt_text_pos = "overlay",
    })
    set_timeout(
        M.conf.flash_t,
        vim.schedule_wrap(function()
            api.nvim_buf_del_extmark(0, flash_ns, flash_id)
            vim.cmd('redraw')
        end))
end

local function search_pos(pattern, mode)
    -- NOTE: moves cursor to match! need to save/restore
    local res
    if mode then
        res = vim.fn.searchpos(pattern, mode)
    else
        res = vim.fn.searchpos(pattern)
    end
    return { line = res[1], col = res[2] }
end

local function dim(visible)
    -- hide highlights, make everything grey.
    for lnum = visible.top - 1, visible.bot - 1 do
        vim.api.nvim_buf_add_highlight(0, background_ns, M.conf.hl.overlay, lnum, 0, -1)
    end
end

local function visible_matches(str)
    -- there are 4 options
    --   1. some matches are visible :  #matches >  0 , next != nil
    --   2.   no matches are visible :  #mathces == 0 , next != nil
    --   3.  all matches are visible :  #matches >  0 , next == nil
    --   4.   no matches             :  #matches == 0 , next == nil

    local save_cursor = api.nvim_win_get_cursor(0) -- save location

    local visible = visible_lines()
    dim(visible)

    local matches = {}
    local seen = new_autotable(2);

    -- Start searching from first visible line
    vim.fn.cursor({ visible.top, 1 })

    -- Storytime: the search() function in vim doesn't accept matches AT
    -- the cursor position. So when I move to the beginning of the visible
    -- range I won't detect matches that are right at the beginning.
    -- The flag "c" lets you accept matches AT cursor position, but that means
    -- that the cursor doesn't move to new matches.
    -- To avoid getting stuck in place I only use "c" on the first search

    local res = search_pos(str, "c")
    while (res.line > 0 --[[ matches found ]]
        and res.line >= visible.top --[[ match is visible ]]
        and res.line <= visible.bot --[[ match is visible ]]
        and seen[res.line][res.col] == nil--[[ new match ]]
        ) do
        seen[res.line][res.col] = true
        table.insert(matches, res)
        res = search_pos(str)
    end

    api.nvim_win_set_cursor(0, save_cursor) -- restore location
    return matches, res.col > 0 and res or nil
end

local function getkey()
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

local function match_and_show(pat, cnt)
    -- delete stale extmarks before drawing new ones
    api.nvim_buf_clear_namespace(0, hint_ns, 0, -1)
    local matches, next = visible_matches(pat)
    local color = (#matches == 1) and "OnesearchSingle" or "OnesearchMulti"
    for _, match in ipairs(matches) do
        api.nvim_buf_set_extmark(0, hint_ns, match.line - 1, match.col - 1, {
            virt_text = { { pat, color } },
            virt_text_pos = "overlay"
        })

        if cnt then
            api.nvim_buf_set_extmark(0, hint_ns, match.line - 1, match.col - 1 + #pat, {
                virt_text = { { cnt, M.conf.hl.error } },
                virt_text_pos = "overlay"
            })
        end
    end
    return matches, next
end

local function select_hint(targets)
    local key = getkey()
    local selected = targets[key]
    if selected then
        api.nvim_win_set_cursor(0, { selected.line, selected.col - 1 })
        if M.conf.flash_t > 0 then
            flash_line(selected.line)
        end
    end
end

--------------------------------------------------------------------------------
-- EXPORTED STUFF
--------------------------------------------------------------------------------

M.conf = {
    flash_t = 150,
    hl = {
        overlay = "LineNr",
        multi = "OnesearchMulti",
        single = "OnesearchSingle",
        select = "WarningMsg",
        flash = "Search",
        error = "WarningMsg",
        prompt_empty = "Todo",
        prompt_matches = "Question",
        prompt_nomatch = "ErrorMsg",
    },
    prompt = ">>> Search: ",
    hints = { "a", "s", "d", "f", "h", "j", "k", "l", "w", "e", "r", "u", "i", "o", "x", "c", "n", "m" }
}
M.last_search = ""
M.last_search_longestmatch = 0

function M.setup(user_conf)
    M.conf = vim.tbl_deep_extend("force", M.conf, user_conf)
end

-- from  https://github.com/phaazon/hop.nvim/blob/baa92e09ea2d3085bdf23c00ab378c1f27069f6f/lua/hop/init.lua#98
function M.search()

    M._search()
    -- Remove extmarks and restore highlighting
    M.clear()
    vim.cmd('redraw')
    api.nvim_echo({ { "", 'Normal' } }, false, {})
end

local function show_hints(matches)
    local targets = {}
    -- remove neon green hints to better see targets
    api.nvim_buf_clear_namespace(0, hint_ns, 0, -1)
    for i, match in ipairs(matches) do
        if i < #M.conf.hints then
            local c = M.conf.hints[i]
            targets[c] = match
            api.nvim_buf_set_extmark(0, hint_ns, match.line - 1, match.col - 1, {
                virt_text = { { c, M.conf.hl.select } },
                virt_text_pos = "overlay"
            })
        end
    end
    return targets
end

function M._search()

    local K_Esc = api.nvim_replace_termcodes('<Esc>', true, false, true) -- you know who I am
    local K_BS = api.nvim_replace_termcodes('<BS>', true, false, true) -- backspace
    local K_CR = api.nvim_replace_termcodes('<CR>', true, false, true) -- enter
    local K_TAB = api.nvim_replace_termcodes('<Tab>', true, false, true)
    local pattern = ''

    local save_cursor = api.nvim_win_get_cursor(0) -- save location

    local next = nil
    local matches, key, longestmatch

    api.nvim_echo({ { M.conf.prompt, M.conf.hl.prompt_empty }, { pattern } }, false, {})
    while (true) do

        dim(visible_lines())
        vim.cmd('redraw')

        key = getkey()

        if not key then return end

        if key == "\x80ku" then -- UP arrow
            pattern = M.last_search
            longestmatch = M.last_search_longestmatch
        elseif key == K_Esc then -- reject
            api.nvim_win_set_cursor(0, save_cursor)
            return
        elseif key == K_CR then
            break -- accept
        elseif key == K_TAB then -- next
            if next then
                api.nvim_win_set_cursor(0, { next.line, next.col })
                api.nvim_exec("normal! zt", false)
            end
        elseif key == K_BS then -- decrease
            if #pattern == 0 then -- delete on empty pattern exits
                return
            end
            pattern = pattern:sub(1, -2)
        else -- increase
            pattern = pattern .. key
        end

        matches, next = match_and_show(pattern)

        if #matches == 0 and next then
            api.nvim_win_set_cursor(0, { next.line, next.col - 1 })
            matches, next = match_and_show(pattern)
        end

        if #matches > 0 then
            longestmatch = #pattern
        end

        if #matches == 0 and not next then
            match_and_show(pattern:sub(0, longestmatch), pattern:sub(longestmatch + 1))
            vim.cmd('redraw')
        end

        local color = M.conf.hl.prompt_empty
        if #pattern > 0 then
            color = M.conf.hl.prompt_matches
        end
        if #pattern > 0 and #matches == 0 then
            color = M.conf.hl.prompt_nomatch
        end
        api.nvim_echo({ { M.conf.prompt, color }, { pattern } }, false, {})
        vim.cmd('redraw')

    end

    if #matches == 0 then
        return
    end

    -- save search information for "n" compatibility and
    -- arrow up replay
    vim.fn.setreg("/", pattern)
    M.last_search = pattern
    M.last_search_longestmatch = longestmatch

    if #matches == 1 then
        local match = matches[1]
        api.nvim_win_set_cursor(0, { match.line, match.col - 1 })
        if M.conf.flash_t > 0 then
            flash_line(match.line)
        end
        return
    end

    if #matches > 1 then
        local targets = show_hints(matches)
        -- make sure to show the new hints
        vim.cmd('redraw')
        select_hint(targets)
        return
    end
end

function M.clear()
    api.nvim_buf_clear_namespace(0, hint_ns, 0, -1)
    api.nvim_buf_clear_namespace(0, background_ns, 0, -1)
end

return M
