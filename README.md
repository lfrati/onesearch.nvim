<p align="center">
  <img width="400" src="https://raw.githubusercontent.com/lfrati/onesearch/main/assets/pony.jpeg">
   <p align="center"> The one-trick pony of searching.
</p>


# 🔎 onesearch.nvim
> "Oh, sure, it can do anything you want." said the old man
> 
>  "As long as what you want is what it does."

### Why onesearch.nvim?
Ever since I discovered plugins like [easymotion](https://github.com/easymotion/vim-easymotion) I've been in love with moving around selecting single char targets. With the advent of lua several new search plugins have appeared but despite their extensive configurability I couldn't get them to fit my specific use case. In particular I wanted it to:
- highlight visible matches and use TAB to look for more matches outside the visible range
- visually show that there is a single match so that I don't have to scan the screen looking for more, and jump to it when I press CR
- accept that I make mistakes and help me recover from them: show me the last valid match while I search and show me where I land so I don't lose track of the cursor when I mistype the target char

## 📦 Installation

Using [vim-plug](https://github.com/junegunn/vim-plug)

```viml
Plug 'lfrati/onesearch.nvim'
  nmap / :lua require('onesearch').search()<CR>
```

Using [dein](https://github.com/Shougo/dein.vim)

```viml
call dein#add('lfrati/onesearch.nvim')
  nmap / :lua require('onesearch').search()<CR>
```

Using [packer](https://github.com/wbthomason/packer.nvim)

```lua
 use { 'lfrati/onesearch.nvim', config = function()
        vim.keymap.set("n", "/", ":lua require('onesearch').search()<CR>")
 end }
```

## ⚙️ How it works

Onesearch has only one main function `search()`, which dims the text on screen and starts an interactive string search. As you type the matches in the currently visible area are highlighted, if there is only a single match the color will change. 

Single matche           |  Multiple matches             | Hints
:-------------------------:|:-------------------------:|:-------------------------:
<img width="363" alt="single" src="https://user-images.githubusercontent.com/3115640/202805162-24a428d5-af68-43bc-8896-8d9a0da5c7f8.png"> | <img width="366" alt="multiple" src="https://user-images.githubusercontent.com/3115640/202805039-cf8839a2-572f-4760-a059-6c73a21f84f9.png"> |  <img width="365" alt="targets" src="https://user-images.githubusercontent.com/3115640/202805101-c22eac31-645e-4171-b3cc-f08343ed8806.png">

Pressing `<Tab>` will loop through groups of matches (`<S-Tab>` will go back). Upon pressing `<CR>` the search ends and the jumping begins. The highlight changes to red, showing single char hints that can be used to jump to the matches. If there is only a single match visible it will jump immediately.

While searching for a pattern, errors (i.e. chars that lead to no matches) are shown in red.

Multiple matches  + errors         |  Single match   + errors           
:-------------------------:|:-------------------------:
<img width="361" alt="multi_error" src="https://user-images.githubusercontent.com/3115640/202805900-55a31562-a93d-4e62-b3a0-cbb6deed9580.png"> | <img width="361" alt="single_errors" src="https://user-images.githubusercontent.com/3115640/202806029-fa438418-aa66-4ab7-b110-b9c4071a01dd.png">

You can delete all the errors with a single press of `<BS>` and continue searching. Also when a target is chosen the corresponding line flashes briefly. This is helpful in case of typos while selecting the target because it avoids losing track of the cursor.

| Landing Flash  | S-Tab Flash |
| ------------- | ------------- |
| <video src="https://user-images.githubusercontent.com/3115640/202806932-80fce90e-4f46-4d0a-bebd-7f17e2687f3e.mov" controls>  | <video src="https://user-images.githubusercontent.com/3115640/202809030-5db6be9c-3cef-4103-b146-37e12bccb3bb.mov" controls>|


## 🎁 Extra goodies
- populate `/` register : use `n` to quickly search for more matches ( see `:help quote_/` )
- set ``` m` ``` : use ``` `` ``` or ``` '' ``` to go back where you came from ( see `:help mark-motions` )
- embrace laziness: don't feel like deleting error? just `<CR>`! don't feel like picking char? just `<CR>`!
- up to 324 default hints : use pairs of hints to select from a large pool of matches, only when needed.

Select first char        |  Select second char        
:-------------------------:|:-------------------------:
<img width="737" alt="CH1" src="https://user-images.githubusercontent.com/3115640/202332071-be69ea72-e88f-4984-8209-0079a4fe792a.png"> | <img width="739" alt="CH2" src="https://user-images.githubusercontent.com/3115640/202332109-04743a7d-43b0-46ef-941c-eed4d025eee3.png">

## 🚀 Configuration
What can I change?
- Don't like the default colors? Pick your own. 
- Don't want flashes? Set flash_t to zero.
- Don't like the chars used for hints? Provide your own[^1].
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
        current_char = "DiffDelete",  -- highlight for char to be chosen from pair
        other_char = "Normal",        -- highlight for other char in the pair
        prompt_empty = "Todo",        -- highlight for prompt upon empty search pattern
        prompt_matches = "Question",  -- highlight for default prompt
        prompt_nomatch = "ErrorMsg",  -- highlight for non-matching prompt
    },
    prompt = ">>> Search: ",          -- prompt header
    hints = { "a", "s", "d", "f", "h", "j", "k", "l", "w", "e", "r", "u", "i", "o", "x", "c", "n", "m" }
}
```
[^1]: Hints are applied top-to-bottom, beacuse when you tab around your cursor is set to the top one.
