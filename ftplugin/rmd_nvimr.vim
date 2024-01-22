
if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'rmd') == -1
    finish
endif

lua require("r.config").real_setup()

let g:Rcfg.rmdchunk = get(g:, "R_rmdchunk", 2)

if g:Rcfg.rmdchunk == 1 || g:Rcfg.rmdchunk == 2
    " Write code chunk in rnoweb files
    inoremap <buffer><silent> ` <Esc>:call RWriteRmdChunk()<CR>a
elseif type(g:Rcfg.rmdchunk) == v:t_string
    exe 'inoremap <buffer><silent> ' . g:Rcfg.rmdchunk . ' <Esc>:call RWriteRmdChunk()<CR>a'
endif

function! RWriteRmdChunk()
    if RmdIsInRCode(0) == 0
        if getline(".") =~ "^\\s*$"
            let curline = line(".")
            call setline(curline, "```{r}")
            if &filetype == 'quarto'
                call append(curline, ["", "```", ""])
                call cursor(curline + 1, 1)
            else
                call append(curline, ["```", ""])
                call cursor(curline, 5)
            endif
            return
        else
            if g:Rcfg.rmdchunk == 2
                exe "normal! a`r `\<Esc>i"
                return
            endif
        endif
    endif
    exe 'normal! a`'
endfunction

function! RmdGetYamlField(field)
    let value = []
    let lastl = line('$')
    let idx = 2
    while idx < lastl
        let line = getline(idx)
        if line == '...' || line == '---'
            break
        endif
        if line =~ '^\s*' . a:field . '\s*:'
            let bstr = substitute(line, '^\s*' . a:field . '\s*:\s*\(.*\)\s*', '\1', '')
            if bstr =~ '^".*"$' || bstr =~ "^'.*'$"
                let bib = substitute(bstr, '"', '', 'g')
                let bib = substitute(bib, "'", '', 'g')
                let bibl = [bib]
            elseif bstr =~ '^\[.*\]$'
                try
                    let l:bbl = eval(bstr)
                catch /.*/
                    call RWarningMsg('YAML line invalid for Vim: ' . line)
                    let bibl = []
                endtry
                if exists('l:bbl')
                    let bibl = l:bbl
                endif
            else
                let bibl = [bstr]
            endif
            for fn in bibl
                call add(value, fn)
            endfor
            break
        endif
        let idx += 1
    endwhile
    if value == []
        return ''
    endif
    if a:field == "bibliography"
        call map(value, "expand(v:val)")
    endif
    return join(value, "\x06")
endfunction

function! RmdIsInPythonCode(vrb)
    let chunkline = search("^[ \t]*```[ ]*{python", "bncW")
    let docline = search("^[ \t]*```$", "bncW")
    if chunkline > docline && chunkline != line(".")
        return 1
    else
        if a:vrb
            call RWarningMsg("Not inside a Python code chunk.")
        endif
        return 0
    endif
endfunction

function! RmdIsInRCode(vrb)
    let chunkline = search("^[ \t]*```[ ]*{r", "bncW")
    let docline = search("^[ \t]*```$", "bncW")
    if chunkline == line(".")
        return 2
    elseif chunkline > docline
        return 1
    else
        if a:vrb
            call RWarningMsg("Not inside an R code chunk.")
        endif
        return 0
    endif
endfunction

function! RmdPreviousChunk() range
    let rg = range(a:firstline, a:lastline)
    let chunk = len(rg)
    for var in range(1, chunk)
        let curline = line(".")
        if RmdIsInRCode(0) == 1 || RmdIsInPythonCode(0)
            let i = search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW")
            if i != 0
                call cursor(i-1, 1)
            endif
        endif
        let i = search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW")
        if i == 0
            call cursor(curline, 1)
            call RWarningMsg("There is no previous R code chunk to go.")
            return
        else
            call cursor(i+1, 1)
        endif
    endfor
    return
endfunction

function! RmdNextChunk() range
    let rg = range(a:firstline, a:lastline)
    let chunk = len(rg)
    for var in range(1, chunk)
        let i = search("^[ \t]*```[ ]*{\\(r\\|python\\)", "nW")
        if i == 0
            call RWarningMsg("There is no next R code chunk to go.")
            return
        else
            call cursor(i+1, 1)
        endif
    endfor
    return
endfunction

" Send Python chunk to R
function! SendRmdPyChunkToR(e, m)
    let chunkline = search("^[ \t]*```[ ]*{python", "bncW") + 1
    let docline = search("^[ \t]*```", "ncW") - 1
    let lines = getline(chunkline, docline)
    let ok = RSourceLines(lines, a:e, 'PythonCode')
    if ok == 0
        return
    endif
    if a:m == "down"
        call RmdNextChunk()
    endif
endfunction


" Send R chunk to R
function! SendRmdChunkToR(e, m)
    if RmdIsInRCode(0) == 2
        call cursor(line(".") + 1, 1)
    endif
    if RmdIsInRCode(0) != 1
        if RmdIsInPythonCode(0) == 0
            call RWarningMsg("Not inside an R code chunk.")
        else
            call SendRmdPyChunkToR(a:e, a:m)
        endif
        return
    endif
    let chunkline = search("^[ \t]*```[ ]*{r", "bncW") + 1
    let docline = search("^[ \t]*```", "ncW") - 1
    let lines = getline(chunkline, docline)
    let ok = RSourceLines(lines, a:e, "chunk")
    if ok == 0
        return
    endif
    if a:m == "down"
        call RmdNextChunk()
    endif
endfunction

let b:IsInRCode = function("RmdIsInRCode")
let b:PreviousRChunk = function("RmdPreviousChunk")
let b:NextRChunk = function("RmdNextChunk")
let b:SendChunkToR = function("SendRmdChunkToR")

let b:rplugin_knitr_pattern = "^``` *{.*}$"

"==========================================================================
" Key bindings and menu items

call RCreateStartMaps()
call RCreateEditMaps()
call RCreateSendMaps()
call RControlMaps()
call RCreateMaps('nvi', 'RSetwd', 'rd', ':call RSetWD()')

" Only .Rmd and .qmd files use these functions:
call RCreateMaps('nvi', 'RKnit',           'kn', ':call RKnit()')
call RCreateMaps('ni',  'RSendChunk',      'cc', ':call b:SendChunkToR("silent", "stay")')
call RCreateMaps('ni',  'RESendChunk',     'ce', ':call b:SendChunkToR("echo", "stay")')
call RCreateMaps('ni',  'RDSendChunk',     'cd', ':call b:SendChunkToR("silent", "down")')
call RCreateMaps('ni',  'REDSendChunk',    'ca', ':call b:SendChunkToR("echo", "down")')
call RCreateMaps('n',   'RNextRChunk',     'gn', ':call b:NextRChunk()')
call RCreateMaps('n',   'RPreviousRChunk', 'gN', ':call b:PreviousRChunk()')

call RSourceOtherScripts()

function! RPDFinit(...)
    exe "source " . substitute(g:rplugin.home, " ", "\\ ", "g") . "/R/pdf_init.vim"
endfunction

call timer_start(1, "RPDFinit")

if exists("b:undo_ftplugin")
    let b:undo_ftplugin .= " | unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR"
else
    let b:undo_ftplugin = "unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR"
endif
