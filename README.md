<p align="center">
  <img width="400" src="https://raw.githubusercontent.com/lfrati/onesearch/main/assets/pony.jpeg">
   <p align="center"> The one-trick pony of searching.
</p>


# onesearch.nvim
What is onesearch? Not his [highness of motion](https://github.com/easymotion/vim-easymotion) nor a mind bending [approach](https://github.com/ggandor/leap.nvim). This pony does one thing and one thing only: interactively searches for a pattern.

## Why onesearch.nvim?
Ever since I discovered plugins like [easymotion](https://github.com/easymotion/vim-easymotion) I've been in love with moving around selecting single char targets. With the advent of lua several new search plugins have appeared but despite their extensive configurability I couldn't get them to fit my specific use case. In particular I wanted to:
- highlight visible matches and use TAB to look for more matches outside the visible range
- show that there is a single match so that I don't have to scan the screen looking for more, and jump to it when I press CR
- help me recover from mistakes: show me the last valid match when I mistype and show me where I land so I don't lose track of the cursor

## Installation
Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
 use { 'lfrati/onesearch.nvim', config = function()
        vim.keymap.set("n", "/", ":lua require('onesearch').search()<CR>")
 end }
```

## How it works

Onesearch has only one main function `search()`, which dims the text on screen and starts an interactive string search. As you type the matches in the currently visible area are highlighted in green, if there is only a single match the color will change to light blue. 

Multiple matches           |  Single match             | Hints
:-------------------------:|:-------------------------:|:-------------------------:
<img width="310" alt="multi" src="https://user-images.githubusercontent.com/3115640/202079543-4f9ef5dd-ca3e-446e-84ef-9cf631163b22.png">   |  <img width="310" alt="single" src="https://user-images.githubusercontent.com/3115640/202079561-9bd3602f-2f17-4da1-8d8f-83120a104738.png"> | <img width="310" alt="hints" src="https://user-images.githubusercontent.com/3115640/202079575-927ebb48-8078-4973-8725-cb8be48898d2.png"> 

Pressing `<Tab>` will loop through groups of matches. Upon pressing `<CR>` the search ends and the jumping begins. The highlight changes to red, showing single char hints that can be used to jump to the matches. If there is only a single match visible it will jump immediately.

```mermaid
graph TD
    A(START) -->|overlay| B(read char)
    B -->|ESC| C(END)
    subgraph pattern
        B --> |char| E(grow) --> B
        B --> |DEL| F(shrink) --> B 
        F --> |empty + DEL| C
        B -->|TAB| G(move view) --> B
        B -->|ENTER| D{Accept}
    end
    subgraph marks
        D --> |single match|J
        D --> |multiple matches|H(read char)
        H --> |char|J(JUMP)
    end
    H --> |ESC|C
```
While searching for a pattern, errors (i.e. chars that lead to no matches) are shown in red.

Multiple matches  + errors         |  Single match   + errors           
:-------------------------:|:-------------------------:
<img width="345" alt="multi_error" src="https://user-images.githubusercontent.com/3115640/202078577-67a9b404-f8d8-4342-9887-d7d478fd9897.png"> | <img width="343" alt="single_error" src="https://user-images.githubusercontent.com/3115640/202078587-d319ad84-915d-46a8-9308-96a793d68e93.png">

You can delete the red character to resume searching. Also when a target is chosen the corresponding line flashes briefly. This is helpful in case of typos while selecting the target because it avoids losing track of the cursor.

![example](https://user-images.githubusercontent.com/3115640/202076941-2c018dc6-33a8-4001-9f99-c402a6ba099c.gif)

## Configuration
The default settings are already perfect, why would you change them?

But if you really want to just override the following defaults:
```lua
require("onesearch").setup{
    flash_t = 150,                    -- how long flash lasts upon landing, set to 0 for no flash
    hl = {
        overlay = "NonText",          -- highlight for the background during search
        multi = "OnesearchMulti",     -- highlight for multiple matches
        single = "OnesearchSingle",   -- highlight for single match
        select = "WarningMsg",        -- highlight for hints during target selection
        flash = "Search",             -- highlight for landing flash
        error = "WarningMsg",         -- highlight for no-matches flash
        prompt_empty = "Todo",        -- highlight for prompt upon empty search pattern
        prompt_matches = "Question",  -- highlight for default prompt
        prompt_nomatch = "ErrorMsg",  -- highlight for non-matching prompt
    },
    prompt = ">>> Search: ",          -- prompt header
    hints = { "a", "s", "d", "f", "h", "j", "k", "l", "w", "e", "r", "u", "i", "o", "x", "c", "n", "m" }
}
```
