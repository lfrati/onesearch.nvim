local M = {}

--------------------------------------------------------------------------------
-- CONF
--------------------------------------------------------------------------------

local api = vim.api
local uv = vim.loop

local hint_ns = vim.api.nvim_create_namespace("OnesearchHints")
local match_ns = vim.api.nvim_create_namespace("OnesearchMatch")
local background_ns = vim.api.nvim_create_namespace("OnesearchBackground")
local flash_ns = vim.api.nvim_create_namespace("OnesearchFlash")

if vim.o.termguicolors == true then -- fun gui colors :)
    -- search
    vim.api.nvim_set_hl(0, 'OnesearchOverlay', { fg = "#59717d", bold = true })
    vim.api.nvim_set_hl(0, 'OnesearchMulti', { fg = "#7fef00", bold = true })
    vim.api.nvim_set_hl(0, 'OnesearchSingle', { fg = "#66ccff", bold = true })
    -- flash
    vim.api.nvim_set_hl(0, 'OnesearchFlash', { fg = "#d4d4d4", bg = "#613315", bold = true })
    -- hint pairs
    vim.api.nvim_set_hl(0, 'OnesearchCurrent', { fg = "#d4d4d4", bg = "#6f1313", bold = true })
    vim.api.nvim_set_hl(0, 'OnesearchOther', { fg = "#d4d4d4", bold = true })
    -- colors
    vim.api.nvim_set_hl(0, 'OnesearchGreen', { fg = "#69a955", bold = true })
    vim.api.nvim_set_hl(0, 'OnesearchYellow', { fg = "#d7ba7d", bold = true })
    vim.api.nvim_set_hl(0, 'OnesearchRed', { fg = "#f44747", bold = true })
    vim.api.nvim_set_hl(0, 'OnesearchBlue', { fg = "#569cd6", bold = true })

else -- boring default colors :(
    -- search
    vim.api.nvim_set_hl(0, 'OnesearchOverlay', { link = "LineNr" })
    vim.api.nvim_set_hl(0, 'OnesearchMulti', { link = "Search" })
    vim.api.nvim_set_hl(0, 'OnesearchSingle', { link = "IncSearch" })
    -- highlight
    vim.api.nvim_set_hl(0, 'OnesearchFlash', { link = "Search" })
    -- hint pairs
    vim.api.nvim_set_hl(0, 'OnesearchCurrent', { link = "DiffDelete" })
    vim.api.nvim_set_hl(0, 'OnesearchOther', { link = "Normal" })
    -- colors
    vim.api.nvim_set_hl(0, 'OnesearchGreen', { link = "Comment" })
    vim.api.nvim_set_hl(0, 'OnesearchYellow', { link = "Todo" })
    vim.api.nvim_set_hl(0, 'OnesearchRed', { link = "WarningMsg" })
    vim.api.nvim_set_hl(0, 'OnesearchBlue', { link = "Question" })
end

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

local function make_pairs(hints)
    local pairs = {}
    for i = 1, #hints do
        for j = 1, #hints do
            pairs[#pairs + 1] = hints[i] .. hints[j]
        end
    end
    return pairs
end

-- local function get_piece(lnum, start, stop)
--     local line = vim.fn.getline(lnum)
--     local chunk = line:sub(start, stop < #line and stop or #line)
--     return chunk
-- end

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

    api.nvim_buf_clear_namespace(0, background_ns, 0, -1)
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
    local key = vim.fn.getchar()

    if type(key) == 'number' then
        key = vim.fn.nr2char(key)
    end
    return key
end

local function match_and_show(head, tail)
    -- delete stale extmarks before drawing new ones
    local matches, next = visible_matches(head)
    local color = (#matches == 1) and "OnesearchSingle" or "OnesearchMulti"
    if tail then
        -- replace " " with "_" so that we see it better, space has no color >_>
        tail = tail:gsub(" ", "_")
    end
    api.nvim_buf_clear_namespace(0, match_ns, 0, -1)
    for _, match in ipairs(matches) do
        local lnum = match.line - 1
        local start_col = match.col - 1
        local end_col = start_col + #head
        api.nvim_buf_set_extmark(0, match_ns, lnum, start_col, {
            hl_group = color,
            end_col = end_col,

        })
        if tail then
            api.nvim_buf_set_extmark(0, match_ns, lnum, end_col, {
                virt_text = { { tail, M.conf.hl.error } },
                virt_text_pos = "overlay"
            })
        end
    end
    return matches, next
end

local function select_hint(matches)
    local targets = {}
    -- remove neon green hints to better see targets
    api.nvim_buf_clear_namespace(0, match_ns, 0, -1)
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

    vim.cmd("redraw")

    local key = getkey()
    local selected = targets[key]
    if selected then
        api.nvim_win_set_cursor(0, { selected.line, selected.col - 1 })
        return true
    end
    return false
end

local function select_hints(matches)

    local function get_chs(x) return x:sub(1, 1), x:sub(2, 2) end

    local targets = new_autotable(2);
    local seen = new_autotable(2);

    -- remove neon green hints
    api.nvim_buf_clear_namespace(0, match_ns, 0, -1)
    for i, match in ipairs(matches) do
        local pair = M.conf.pairs[i]
        local ch1, ch2 = get_chs(pair)
        local row = seen[match.line]
        if not row[match.col - 1] and not row[match.col + 1] then
            row[match.col] = true
            api.nvim_buf_set_extmark(0, hint_ns, match.line - 1, match.col - 1, {
                virt_text = { { ch1, M.conf.hl.current_char } },
                virt_text_pos = "overlay",
            })
            api.nvim_buf_set_extmark(0, hint_ns, match.line - 1, match.col, {
                virt_text = { { ch2, M.conf.hl.other_char } },
                virt_text_pos = "overlay",
            })
            match.head = ch1
            match.col = match.col + 1
            targets[ch1][ch2] = match
        end
    end

    vim.cmd("redraw")

    local k1 = getkey()
    local selected = targets[k1]

    -- what an ugly way to check if a table is empty...
    if next(selected) == nil then
        return false -- pressed some random garbage
    end

    -- remove previous targets
    api.nvim_buf_clear_namespace(0, hint_ns, 0, -1)
    targets = {}
    for c, match in pairs(selected) do
        api.nvim_buf_set_extmark(0, hint_ns, match.line - 1, match.col - 2, {
            virt_text = { { match.head, M.conf.hl.other_char } },
            virt_text_pos = "overlay",
        })
        api.nvim_buf_set_extmark(0, hint_ns, match.line - 1, match.col - 1, {
            virt_text = { { c, M.conf.hl.current_char } },
            virt_text_pos = "overlay"
        })
        targets[c] = match
    end

    vim.cmd("redraw")

    local k2 = getkey()
    selected = targets[k2]

    if selected then
        api.nvim_win_set_cursor(0, { selected.line, selected.col - 2 })
        return true
    end

    return false

end

--------------------------------------------------------------------------------
-- EXPORTED STUFF
--------------------------------------------------------------------------------

M.conf = {
    flash_t = 150,
    hl = {
        overlay = "OnesearchOverlay",
        multi = "OnesearchMulti",
        single = "OnesearchSingle",
        select = "OnesearchRed",
        flash = "OnesearchFlash",
        error = "OnesearchRed",
        current_char = "OnesearchCurrent",
        other_char = "OnesearchOther",
        prompt_empty = "OnesearchYellow",
        prompt_matches = "OnesearchGreen",
        prompt_nomatch = "OnesearchRed",
    },
    prompt = ">>> Search: ",
    hints = { "a", "s", "d", "f", "h", "j", "k", "l", "w", "e", "r", "u", "i", "o", "x", "c", "n", "m" }
}
M.conf.pairs = make_pairs(M.conf.hints)
M.last_search = ""

function M.setup(user_conf)
    M.conf = vim.tbl_deep_extend("force", M.conf, user_conf or {})
    M.conf.pairs = make_pairs(M.conf.hints)
end

-- from  https://github.com/phaazon/hop.nvim/blob/baa92e09ea2d3085bdf23c00ab378c1f27069f6f/lua/hop/init.lua#98
function M.search()

    -- :help mark-motions
    -- Set the previous context mark.  This can be jumped to with:
    --      - '' go to the line
    --      - `` go to the position
    api.nvim_exec("normal! m`", false)

    -- :help winsaveview()
    -- This is useful if you have a mapping that jumps around in the
    -- buffer and you want to go back to the original view.
    local save_winview = vim.fn.winsaveview()
    local prev_guicursor = vim.o.guicursor
    vim.o.guicursor = "n:ver100"

    local ok, retval = pcall(M._search)
    if not ok then
        api.nvim_echo({ { retval, 'Error' } }, true, {})
    end

    M.clear()
    vim.o.guicursor = prev_guicursor

    -- retval is true if jumped
    --          false if aborted
    if not retval then
        vim.fn.winrestview(save_winview)
        api.nvim_echo({ { "", 'Normal' } }, false, {})
    else
        if M.conf.flash_t > 0 then
            local line = vim.fn.getpos(".")[2]
            flash_line(line)
        end
    end
end

function M._search()

    local K_Esc = api.nvim_replace_termcodes('<Esc>', true, false, true) -- you know who I am
    local K_BS = api.nvim_replace_termcodes('<BS>', true, false, true) -- backspace
    local K_CR = api.nvim_replace_termcodes('<CR>', true, false, true) -- enter
    local K_TAB = api.nvim_replace_termcodes('<Tab>', true, false, true)
    local pattern = ''

    local next = nil
    local matches, key
    local color = M.conf.hl.prompt_empty
    local last_match = ""

    dim(visible_lines())

    while (true) do

        api.nvim_echo({ { M.conf.prompt, color }, { pattern, "Normal" } }, false, {})
        vim.cmd("redraw")

        key = getkey()

        if key == K_Esc then -- reject
            return false
        elseif key == K_CR then
            break -- accept
        elseif key == K_TAB then -- next
            if next then
                api.nvim_win_set_cursor(0, { next.line, next.col })
                api.nvim_exec("normal! zt", false)
            end
        elseif key == K_BS then -- decrease
            if #pattern == 0 then -- delete on empty pattern exits
                return false
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
            last_match = pattern
        end

        if #matches == 0 and not next then
            match_and_show(pattern:sub(0, #last_match), pattern:sub(#last_match + 1))
        end

        color = M.conf.hl.prompt_empty
        if #pattern > 0 then
            color = M.conf.hl.prompt_matches
        end
        if #pattern > 0 and #matches == 0 then
            color = M.conf.hl.prompt_nomatch
        end


    end

    pattern = last_match
    matches, next = visible_matches(pattern)

    if #matches <= 0 then
        return false
    end

    -- :help quote_/
    -- Contains the most recent search-pattern.
    -- This is used for "n" and 'hlsearch'.
    vim.fn.setreg("/", pattern)

    if #matches == 1 then
        local match = matches[1]
        api.nvim_win_set_cursor(0, { match.line, match.col - 1 })
        return true
    end

    if #matches < #M.conf.hints then
        return select_hint(matches)
    end

    if #matches < #M.conf.pairs then
        return select_hints(matches)
    end

    error("Bruh. Too many targets.")

    return false
end

function M.clear()
    api.nvim_buf_clear_namespace(0, hint_ns, 0, -1)
    api.nvim_buf_clear_namespace(0, background_ns, 0, -1)
    api.nvim_buf_clear_namespace(0, match_ns, 0, -1)
end

return M
