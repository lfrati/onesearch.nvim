local M = {}
local api = vim.api
local uv = vim.loop

-- https://stevedonovan.github.io/ldoc/manual/doc.md.html

--------------------------------------------------------------------------------
-- WARNING: 99% of the complexity and the pain in this code comes from figuring
--          out if values should be 1-indexed or 0-indexed or (1,0)-indexed,
--          yeah, (1,0), that's a thing. :help nvim_win_get_cursor()
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- CONF
--------------------------------------------------------------------------------

local hint_ns = vim.api.nvim_create_namespace("OnesearchHints")
local match_ns = vim.api.nvim_create_namespace("OnesearchMatch")
local background_ns = vim.api.nvim_create_namespace("OnesearchBackground")
local flash_ns = vim.api.nvim_create_namespace("OnesearchFlash")


-- from https://jdhao.github.io/2020/09/22/highlight_groups_cleared_in_nvim/
-- some colorschemes can clear existing highlights >_>
-- to make sure our colors works we set them every time search is started
function M.set_colors()
    if vim.o.termguicolors == true then -- fun gui colors :)
        -- search
        vim.api.nvim_set_hl(0, 'OnesearchOverlay', { fg = "#59717d", bold = true })
        vim.api.nvim_set_hl(0, 'OnesearchMulti', { fg = "#7fef00", bold = true })
        vim.api.nvim_set_hl(0, 'OnesearchSingle', { fg = "#000000", bg = "#7fef00", bold = true })
        -- flash
        vim.api.nvim_set_hl(0, 'OnesearchFlash', { fg = "#d4d4d4", bg = "#613315", bold = true })
        -- hint pairs
        vim.api.nvim_set_hl(0, 'OnesearchCurrent', { fg = "#d4d4d4", bg = "#6f1313", bold = true })
        vim.api.nvim_set_hl(0, 'OnesearchOther', { fg = "#d4d4d4", bold = true })
        -- colors
        vim.api.nvim_set_hl(0, 'OnesearchGreen', { fg = "#69a955", bold = true })
        vim.api.nvim_set_hl(0, 'OnesearchYellow', { fg = "#d7ba7d", bold = true })
        vim.api.nvim_set_hl(0, 'OnesearchOrange', { fg = "#ff9900", bold = true })
        vim.api.nvim_set_hl(0, 'OnesearchRed', { fg = "#f44747", bold = true })
        vim.api.nvim_set_hl(0, 'OnesearchBlue', { fg = "#569cd6", bold = true })
        vim.api.nvim_set_hl(0, 'OnesearchOrange', { fg = "#ff9933", bold = true })

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
end

--------------------------------------------------------------------------------
-- UTILS
--------------------------------------------------------------------------------

-- from :help uv.new_timer()
local function set_timeout(timeout, callback)
    local timer = uv.new_timer()
    if timer then
        timer:start(timeout, 0, function()
            timer:stop()
            timer:close()
            callback()
        end)
    end
    return timer
end

-- is this seriously not a default string method?
local function lpad(str, len, char)
    return str .. string.rep(char or " ", len - #str)
end

local function mask_line(lnum)
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

local function get_piece_between(lnum, start, stop)
    local line = vim.fn.getline(lnum)
    local piece = line:sub(start, stop < #line and stop or #line)
    return piece
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
            table.insert(pairs, { hints[i], hints[j] })
        end
    end
    return pairs
end

local function getkey()
    local key = vim.fn.getchar()
    if type(key) == 'number' then
        return vim.fn.nr2char(key)
    end
    return key
end

--------------------------------------------------------------------------------
-- LOCAL STUFF
--------------------------------------------------------------------------------

local function flash_line(lnum)
    -- I sometimes mistype the jump location and I have then to look for
    -- where my cursor went. I'm gonna make the landing line flash to
    -- help me find it more easily.
    local mask = mask_line(lnum)
    local flash_id = api.nvim_buf_set_extmark(0, flash_ns, lnum - 1, 0, {
        virt_text = { { mask, M.conf.hl.flash } },
        virt_text_pos = "overlay"
    })
    set_timeout(
        M.conf.flash_t,
        vim.schedule_wrap(function()
            api.nvim_buf_del_extmark(0, flash_ns, flash_id)
            vim.cmd("redraw")
        end))
end

--- Search for a pattern, after escaping it
--  and return the first match
-- @param pattern : string to be escaped and searched
-- @param    mode : string to be passed to vim.fn.search_pos
-- @return table containing the match info {head, line, start_col, end_col}
-- @warning if the pattern is not found lnum = 0 -> line < 0
-- @warning search is performed from the current cursor position
-- @usage search_pos(".ciao","cW")
local function search_pos(pattern, mode)
    -- NOTE: moves cursor to the match unless mode contains "c"!
    --       This is intented behaviour because the next calls are
    --       going to start from there.

    local escaped = vim.fn.escape(pattern, '\\/.$^~[]*')

    local lnum, col
    if mode then
        lnum, col = unpack(vim.fn.searchpos(escaped, mode))
    else
        lnum, col = unpack(vim.fn.searchpos(escaped))
    end

    return {
        head = get_piece_between(lnum, col, col + #pattern - 1),
        line = lnum - 1,
        start_col = col - 1,
        end_col = col - 1 + #pattern
    }
end

local function dim(visible)
    -- hide highlights, make everything grey.
    api.nvim_buf_clear_namespace(0, background_ns, 0, -1)
    for lnum = visible.top - 1, visible.bot - 1 do
        vim.api.nvim_buf_add_highlight(0, background_ns, M.conf.hl.overlay, lnum, 0, -1)
    end
end

local function visible_matches(head, tail)
    -- there are 4 options
    --   1. some matches are visible :  #matches >  0 , next != nil
    --   2.   no matches are visible :  #mathces == 0 , next != nil
    --   3.  all matches are visible :  #matches >  0 , next == nil
    --   4.   no matches             :  #matches == 0 , next == nil

    -- Storytime: unbeknownst to me, and afaik absent from vimdocs, vim.fn.searchpos()
    --            defaults to searching the previous search if the pattern searched for
    --            is ""... so I manually stop this nonsense by checking for it.
    if #head <= 0 then
        return {}, nil, M.conf.hl.multi
    end

    tail = tail or ""

    local matches = {}
    local seen = new_autotable(2);
    local save_cursor = api.nvim_win_get_cursor(0) -- save location
    local visible = visible_lines()
    dim(visible)

    -- because of the scrolloff lines could be visible that contain
    -- matches from previous iterations.
    -- Ergo don't highligh in the scrolloff margin, unless it's the top of the file.
    if visible.top > vim.o.scrolloff then
        vim.fn.cursor({ visible.top + vim.o.scrolloff, 1 })
    else
        vim.fn.cursor({ visible.top, 1 })
    end

    -- Storytime: the search() function in vim doesn't accept matches AT
    -- the cursor position. So when I move to the beginning of the visible
    -- range I won't detect matches that are right at the beginning.
    -- The flag "c" lets you accept matches AT cursor position, but that means
    -- that the cursor doesn't move to new matches.
    -- To avoid getting stuck in place I only use "c" on the first search

    local res = search_pos(head, "c")
    while (res.line >= 0 --[[ matches found ]]
        and res.line + 1 >= visible.top --[[ match is visible ]]
        and res.line + 1 <= visible.bot --[[ match is visible ]]
        and not seen[res.line][res.start_col]--[[ new match ]]
        ) do
        res.tail = tail -- add the tail information
        -- consecutive matches make double hints a mess, we don't need them anyways
        -- TEST: lllllllllllllllllllllll  should only highlight every third l
        if not seen[res.line][res.start_col - 1]
            and not seen[res.line][res.start_col - 2] then
            seen[res.line][res.start_col] = true
            table.insert(matches, res)
        end
        res = search_pos(head)
    end
    api.nvim_win_set_cursor(0, save_cursor) -- restore location

    local color_head = (#matches == 1) and M.conf.hl.single or M.conf.hl.multi
    return matches, res.start_col >= 0 and res or nil, color_head
end

local function show(matches, color_head, color_tail)
    color_head = color_head or "Search"
    color_tail = color_tail or "Search"
    -- delete stale extmarks before drawing new ones

    api.nvim_buf_clear_namespace(0, match_ns, 0, -1)
    for _, match in ipairs(matches) do
        api.nvim_buf_set_extmark(0, match_ns, match.line, match.start_col, {
            virt_text = { { match.head, color_head } },
            virt_text_pos = "overlay"
        })

        if #match.tail > 0 then
            api.nvim_buf_set_extmark(0, match_ns, match.line, match.end_col, {
                virt_text = { { match.tail, color_tail } },
                virt_text_pos = "overlay"
            })
        end
    end
    return matches, next
end

local function select(matches, color_head, color_tail, match_key)
    show(matches, color_head, color_tail)
    vim.cmd("redraw")

    local key = getkey()
    if key == M.K_CR then -- can't be bothered to pick, go to first one
        key = M.conf.hints[1]
    end

    local remaining = {}
    for _, match in ipairs(matches) do
        if match[match_key] == key then
            table.insert(remaining, match)
        end
    end

    return remaining
end

--------------------------------------------------------------------------------
-- EXPORTED STUFF
--------------------------------------------------------------------------------

M.conf = {
    flash_t = 150,
    scrolloff = 5,
    hl = {
        overlay = "OnesearchOverlay",
        multi = "OnesearchMulti",
        single = "OnesearchSingle",
        select = "OnesearchRed",
        flash = "OnesearchFlash",
        error = "OnesearchRed",
        current_char = "OnesearchRed",
        other_char = "OnesearchOther",
        prompt_empty = "OnesearchYellow",
        prompt_matches = "OnesearchGreen",
        prompt_nomatch = "OnesearchRed",
    },
    prompt = ">>> Search: ",
    hints = { "a", "s", "d", "f", "h", "j", "k", "l", "w", "e", "r", "u", "i", "o", "x", "c", "n", "m" }
}
M.conf.pairs = make_pairs(M.conf.hints)
M.K_Esc = api.nvim_replace_termcodes('<Esc>', true, false, true)
M.K_BS = api.nvim_replace_termcodes('<BS>', true, false, true) -- backspace
M.K_CR = api.nvim_replace_termcodes('<CR>', true, false, true) -- enter
M.K_TAB = api.nvim_replace_termcodes('<Tab>', true, false, true)
M.K_STAB = api.nvim_replace_termcodes('<S-Tab>', true, false, true)
M.K_UpArrow = api.nvim_replace_termcodes('<Up>', true, false, true)
M.K_DownArrow = api.nvim_replace_termcodes('<Down>', true, false, true)
M.last_search = ""
M.debug = false
M.debug_info = nil

function M.setup(user_conf)
    M.conf = vim.tbl_deep_extend("force", M.conf, user_conf or {})
    M.conf.pairs = make_pairs(M.conf.hints)
end

local function search()
    local pattern = ''

    local matches, key, next, color_head
    local stack = {}
    local color = M.conf.hl.prompt_empty
    local last_match = ""
    local errors = ""
    local search_index = 0
    -- do the first dimming manually the others are handled by match_and_show
    dim(visible_lines())

    while (true) do

        api.nvim_echo({ { M.conf.prompt, color }, { last_match, "Normal" }, { errors, M.conf.hl.error } }, false, {})
        vim.cmd("redraw")

        key = getkey()

        if key == M.K_Esc then -- reject
            return false
        elseif key == M.K_CR then
            break -- accept
        elseif key == M.K_TAB then -- next
            -- when tabbing around don't show the top matches at the very top
            -- of the file, it's not very readable
            vim.o.scrolloff = M.conf.scrolloff
            if next then
                table.insert(stack, vim.fn.winsaveview())
                api.nvim_win_set_cursor(0, { next.line + 1, next.end_col })
                if M.conf.alican_super_secret_functionality then
                    flash_line(next.line + 1)
                end
                api.nvim_exec("normal! zt", false)
            end
        elseif key == M.K_STAB then -- next
            if #stack > 0 then
                local prev = table.remove(stack)
                vim.fn.winrestview(prev)
                if M.conf.flash_t > 0 then
                    flash_line(prev.lnum)
                end
            end
        elseif key == M.K_BS then -- decrease

            if #pattern > #last_match then -- there were errors, discard them
                pattern = last_match
            else
                pattern = pattern:sub(1, -2)
                if #pattern <= 0 then
                    last_match = pattern
                end
            end

	elseif key == M.K_UpArrow then -- show last searched pattern
	    search_index = search_index - 1 
	    if search_index < -vim.fn.histnr("search") then
	    	search_index = 0
	    end 
	    pattern = vim.fn.histget("search", search_index) or ""

        elseif key == M.K_DownArrow then -- show first searched pattern
	    search_index = search_index + 1
	    if search_index > vim.fn.histnr("search") then
		    search_index = 0
	    end
            pattern = vim.fn.histget("search", search_index) or ""

        else -- increase
            pattern = pattern .. key
        end

        matches, next, color_head = visible_matches(pattern)
        show(matches, color_head)

        -- the chosen pattern is not visible but exists somewhere: go there
        if #matches == 0 and next then
            api.nvim_win_set_cursor(0, { next.line + 1, next.start_col })
            -- #matches > 0 since it contains the prev next
            matches, next, color_head = visible_matches(pattern)
            show(matches, color_head)
        end

        if #matches > 0 then
            last_match = pattern
            errors = ""
        else
            -- #matches == 0
            if not next then
                -- either the pattern is empty or I have messed up something
                errors = pattern:sub(#last_match + 1):gsub(" ", "_")
                matches, next, color_head = visible_matches(last_match, errors)
                show(matches, color_head, M.conf.hl.error)
            end
        end

        color = M.conf.hl.prompt_empty
        if #pattern > 0 then
            color = M.conf.hl.prompt_matches
        end
        if #pattern > 0 and #matches == 0 then
            color = M.conf.hl.prompt_nomatch
        end
    end

    ------------------------------------------
    -- from here the user pressed CR to accept
    ------------------------------------------

    if #matches <= 0 then
        return false
    end

    -- if the user was lazy and pressed CR when there were errors ignore them >_>
    pattern = last_match
    vim.fn.histadd("search", pattern)

    -- :help quote_/
    -- Contains the most recent search-pattern.
    -- This is used for "n" and 'hlsearch'.
    vim.fn.setreg("/", pattern)

    if #matches == 1 then
        local match = matches[1]
        return { match.line + 1, match.start_col }
    end

    if #matches < #M.conf.hints then
        for i, match in ipairs(matches) do
            match.head = ""
            match.end_col = match.start_col
            match.tail = M.conf.hints[i]
        end
        local selected = select(matches, "Normal", M.conf.hl.select, "tail")

        -- if you mistype during single label selection we won't send you all the way back.
        -- you wanted to be somewhere here, but fucked up. Let's leave you in the neighborhood.
        if #selected == 0 then
            return { matches[1].line + 1, matches[1].start_col }
        end
        -- yay you correctly selected a hint. Let's go there.
        if #selected == 1 then
            return { selected[1].line + 1, selected[1].start_col }
        end
        return nil
    end

    -- TODO: I think there is no point in using the same "put you in the neighborhood" approach
    --       for hint pairs since there is so many of them. Should we still do it?
    if #matches < #M.conf.pairs then
        for i, match in ipairs(matches) do
            match.head = M.conf.pairs[i][1]
            match.end_col = match.start_col + 1
            match.tail = M.conf.pairs[i][2]
        end
        -- select first hint
        matches = select(matches, M.conf.hl.current_char, M.conf.hl.other_char, "head")
        if #matches <= 0 then
            return nil
        end
        -- select second hint
        local selected = select(matches, M.conf.hl.other_char, M.conf.hl.current_char, "tail")
        if #selected == 1 then
            return { selected[1].line + 1, selected[1].start_col }
        end
        return nil
    end

    error("Bruh. Too many targets.")

    return nil
end

-- Some useful options that should be set while searching.
M.VimContext = {
    ["modes"] = {
        ["o"] = {
            ["guicursor"] = "n:ver100",
            ["hlsearch"] = false,
            ["cursorline"] = false,
            ["scrolloff"] = 0
        }
    },
    ["stored"] = {}
}

function M.VimContext:install()
    assert(next(self.stored) == nil, "Stored context is not empty. Installing again will overwrite it")
    for mode, values in pairs(self.modes) do
        self.stored[mode] = {}
        for k, v in pairs(values) do
            local tmp = vim[mode][k]
            self.stored[mode][k] = tmp
            vim[mode][k] = v
        end
    end
end

function M.VimContext:restore()
    for mode, values in pairs(self.stored) do
        for k, v in pairs(values) do
            vim[mode][k] = v
        end
    end
    self.stored = {}
end

function M.search()
    M.set_colors()
    M.debug_info = nil

    -- :help mark-motions
    -- Set the previous context mark.  This can be jumped to with:
    --      - '' go to the line
    --      - `` go to the position
    api.nvim_exec("normal! m`", false)

    -- :help winsaveview()
    -- This is useful if you have a mapping that jumps around in the
    -- buffer and you want to go back to the original view.
    local save_winview = vim.fn.winsaveview()

    M.VimContext:install()

    local ok, retval = pcall(search)

    if not ok then
        if M.debug then
            print(vim.inspect(M.debug_info))
        end
        api.nvim_echo({ { retval, 'Error' } }, true, {})
    end

    M.clear()
    M.VimContext:restore()

    -- retval is true if jumped
    --          false if aborted
    if not retval then
        vim.fn.winrestview(save_winview)
        api.nvim_echo({ { "Onesearch aborted.", 'Normal' } }, false, {})
    else
        api.nvim_win_set_cursor(0, retval)
        if M.conf.flash_t > 0 then
            local line = vim.fn.getpos(".")[2]
            flash_line(line)
        end
        api.nvim_echo({ { "Jumped to match [" .. retval[1] .. "," .. retval[2] .. "]", 'Normal' } }, false, {})
    end
end

function M.clear()
    api.nvim_buf_clear_namespace(0, hint_ns, 0, -1)
    api.nvim_buf_clear_namespace(0, background_ns, 0, -1)
    api.nvim_buf_clear_namespace(0, match_ns, 0, -1)
end

return M
