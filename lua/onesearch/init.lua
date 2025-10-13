local M = {}
local api = vim.api
-- local uv = vim.loop

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
        MT[i] = {
            __index = function(t, k)
                if i < dim then
                    t[k] = setmetatable({}, MT[i + 1])
                    return t[k];
                end
            end
        }
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
-- RENDERING
--------------------------------------------------------------------------------

local Renderer = {}

function Renderer.flash_line(lnum)
    -- I sometimes mistype the jump location and I have then to look for
    -- where my cursor went. I'm gonna make the landing line flash to
    -- help me find it more easily.
    vim.hl.range(0, flash_ns, M.conf.hl.flash, { lnum - 1, 0 }, { lnum - 1, -1 }, { timeout = M.conf.flash_t })
end

function Renderer.dim(visible)
    -- hide previous highlights by overlaying the visible region.
    api.nvim_buf_clear_namespace(0, background_ns, 0, -1)
    vim.hl.range(0, background_ns, M.conf.hl.overlay, { visible.top - 1, 0 }, { visible.bot, -1 })
end

function Renderer.show(matches, color_head, color_tail)
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
    return matches
end

--------------------------------------------------------------------------------
-- LOCAL STUFF
--------------------------------------------------------------------------------

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
    Renderer.dim(visible)

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
            and not seen[res.line][res.start_col] --[[ new match ]]
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

local function select(matches, color_head, color_tail, match_key)
    Renderer.show(matches, color_head, color_tail)
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
-- SEARCH SESSION
--------------------------------------------------------------------------------

local SearchSession = {}
SearchSession.__index = SearchSession

function SearchSession.new(seed)
    local self = setmetatable({
        pattern = '',
        last_match = '',
        errors = '',
        matches = {},
        next_match = nil,
        color_head = M.conf.hl.multi,
        color = M.conf.hl.prompt_empty,
        stack = {},
        search_index = 0,
    }, SearchSession)

    Renderer.dim(visible_lines())

    if seed and #seed > 0 then
        self:apply_seed(seed)
    else
        self:update_prompt_color()
    end

    return self
end

function SearchSession:apply_seed(seed)
    self.matches, self.next_match, self.color_head = visible_matches(seed)
    Renderer.show(self.matches, self.color_head)

    if #self.matches > 0 then
        self.pattern = seed
        self.last_match = seed
        self.errors = ""
    else
        self.pattern = ''
        self.last_match = ''
        self.errors = seed
    end

    self:update_prompt_color()
end

function SearchSession:update_matches()
    self.matches, self.next_match, self.color_head = visible_matches(self.pattern)
    Renderer.show(self.matches, self.color_head)

    if #self.matches == 0 and self.next_match then
        api.nvim_win_set_cursor(0, { self.next_match.line + 1, self.next_match.start_col })
        self.matches, self.next_match, self.color_head = visible_matches(self.pattern)
        Renderer.show(self.matches, self.color_head)
    end

    if #self.matches > 0 then
        self.last_match = self.pattern
        self.errors = ""
    elseif not self.next_match then
        self.errors = self.pattern:sub(#self.last_match + 1):gsub(" ", "_")
        self.matches, self.next_match, self.color_head = visible_matches(self.last_match, self.errors)
        Renderer.show(self.matches, self.color_head, M.conf.hl.error)
    end

    self:update_prompt_color()
end

function SearchSession:update_prompt_color()
    self.color = M.conf.hl.prompt_empty
    if #self.pattern > 0 then
        self.color = M.conf.hl.prompt_matches
    end
    if #self.pattern > 0 and #self.matches == 0 then
        self.color = M.conf.hl.prompt_nomatch
    end
end

function SearchSession:render_prompt()
    api.nvim_echo({ { M.conf.prompt, self.color }, { self.last_match, "Normal" }, { self.errors, M.conf.hl.error } },
        false, {})
    vim.cmd("redraw")
end

function SearchSession:add_character(char)
    self.pattern = self.pattern .. char
end

function SearchSession:backspace()
    if #self.pattern > #self.last_match then
        self.pattern = self.last_match
    else
        self.pattern = self.pattern:sub(1, -2)
        if #self.pattern <= 0 then
            self.last_match = ""
        end
    end
end

function SearchSession:history_prev()
    self.search_index = self.search_index - 1
    if self.search_index < -vim.fn.histnr("search") then
        self.search_index = 0
    end
    self.pattern = vim.fn.histget("search", self.search_index) or ""
end

function SearchSession:history_next()
    self.search_index = self.search_index + 1
    if self.search_index > vim.fn.histnr("search") then
        self.search_index = 0
    end
    self.pattern = vim.fn.histget("search", self.search_index) or ""
end

function SearchSession:jump_to_next_view()
    vim.o.scrolloff = M.conf.scrolloff
    if self.next_match then
        table.insert(self.stack, vim.fn.winsaveview())
        api.nvim_win_set_cursor(0, { self.next_match.line + 1, self.next_match.end_col })
        if M.conf.alican_super_secret_functionality then
            Renderer.flash_line(self.next_match.line + 1)
        end
        vim.cmd.normal({ bang = true, args = { "zt" } })
    end
end

function SearchSession:jump_to_previous_view()
    if #self.stack > 0 then
        local prev = table.remove(self.stack)
        vim.fn.winrestview(prev)
        if M.conf.flash_t > 0 then
            Renderer.flash_line(prev.lnum)
        end
    end
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
        current_char = "OnesearchCurrent",
        other_char = "OnesearchOther",
        prompt_empty = "OnesearchYellow",
        prompt_matches = "OnesearchGreen",
        prompt_nomatch = "OnesearchRed",
    },
    prompt = "[DEV] >>> Search: ",
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

local function search(seed)
    local session = SearchSession.new(seed)

    while true do
        session:render_prompt()

        local key = getkey()

        if key == M.K_Esc then -- reject
            return false
        elseif key == M.K_CR then
            break
        elseif key == M.K_TAB then
            session:jump_to_next_view()
        elseif key == M.K_STAB then
            session:jump_to_previous_view()
        elseif key == M.K_BS then
            session:backspace()
        elseif key == M.K_UpArrow then
            session:history_prev()
        elseif key == M.K_DownArrow then
            session:history_next()
        else
            session:add_character(key)
        end

        if key ~= M.K_CR then
            session:update_matches()
        end
    end

    ------------------------------------------
    -- from here the user pressed CR to accept
    ------------------------------------------

    if #session.matches <= 0 then
        return false
    end

    -- if the user was lazy and pressed CR when there were errors ignore them >_>
    local pattern = session.last_match
    vim.fn.histadd("search", pattern)

    -- :help quote_/
    -- Contains the most recent search-pattern.
    -- This is used for "n" and 'hlsearch'.
    vim.fn.setreg("/", pattern)

    if #session.matches == 1 then
        local match = session.matches[1]
        return { match.line + 1, match.start_col }
    end

    if #session.matches < #M.conf.hints then
        for i, match in ipairs(session.matches) do
            match.head = ""
            match.end_col = match.start_col
            match.tail = M.conf.hints[i]
        end
        local selected = select(session.matches, "Normal", M.conf.hl.select, "tail")

        -- if you mistype during single label selection we won't send you all the way back.
        -- you wanted to be somewhere here, but fucked up. Let's leave you in the neighborhood.
        if #selected == 0 then
            return { session.matches[1].line + 1, session.matches[1].start_col }
        end
        -- yay you correctly selected a hint. Let's go there.
        if #selected == 1 then
            return { selected[1].line + 1, selected[1].start_col }
        end
        return nil
    end

    -- TODO: I think there is no point in using the same "put you in the neighborhood" approach
    --       for hint pairs since there is so many of them. Should we still do it?
    if #session.matches < #M.conf.pairs then
        for i, match in ipairs(session.matches) do
            match.head = M.conf.pairs[i][1]
            match.end_col = match.start_col + 1
            match.tail = M.conf.pairs[i][2]
        end
        -- select first hint
        local remaining = select(session.matches, M.conf.hl.current_char, M.conf.hl.other_char, "head")
        if #remaining <= 0 then
            return nil
        end
        -- select second hint
        local selected = select(remaining, M.conf.hl.other_char, M.conf.hl.current_char, "tail")
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

function M.get_visual_selection()
    local s_start = vim.fn.getpos("'<")
    local s_end = vim.fn.getpos("'>")
    local n_lines = math.abs(s_end[2] - s_start[2]) + 1
    local lines = vim.api.nvim_buf_get_lines(0, s_start[2] - 1, s_end[2], false)
    lines[1] = string.sub(lines[1], s_start[3], -1)
    if n_lines == 1 then
        lines[n_lines] = string.sub(lines[n_lines], 1, s_end[3] - s_start[3] + 1)
    else
        lines[n_lines] = string.sub(lines[n_lines], 1, s_end[3])
    end
    return table.concat(lines, '\n')
end

function M.visual_search()
    M.search(M.get_visual_selection())
end

function M.search(seed)
    M.set_colors()
    M.debug_info = nil

    -- :help mark-motions
    -- Set the previous context mark.  This can be jumped to with:
    --      - '' go to the line
    --      - `` go to the position
    vim.cmd.normal({ bang = true, args = { "m`" } })

    -- :help winsaveview()
    -- This is useful if you have a mapping that jumps around in the
    -- buffer and you want to go back to the original view.
    local save_winview = vim.fn.winsaveview()

    M.VimContext:install()

    local ok, retval = pcall(search, seed)

    if not ok then
        if M.debug then
            print(vim.inspect(M.debug_info))
        end
        api.nvim_echo({ { retval, 'Error' } }, true, {})
    end

    M.clear()
    M.VimContext:restore()

    -- retval is { line, col } when we jumped
    --          false or nil when we aborted
    if not retval then
        vim.fn.winrestview(save_winview)
        api.nvim_echo({ { "Onesearch aborted.", 'Normal' } }, false, {})
    else
        api.nvim_win_set_cursor(0, retval)
        if M.conf.flash_t > 0 then
            local line = vim.fn.getpos(".")[2]
            Renderer.flash_line(line)
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
