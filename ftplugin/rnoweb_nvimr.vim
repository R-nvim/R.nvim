
if exists("g:R_filetypes") && type(g:R_filetypes) == v:t_list && index(g:R_filetypes, 'rnoweb') == -1
    finish
endif

lua require("r.config").real_setup()

if g:Rcfg.rnowebchunk
    " Write code chunk in rnoweb files
    inoremap <buffer><silent> < <Esc>:call RWriteChunk()<CR>a
endif

exe "source " . substitute(g:rplugin.home, " ", "\\ ", "g") . "/R/rnw_fun.vim"

function! s:CompleteEnv(base)
    " List from LaTeX-Box
    let lenv = ['abstract]', 'align*}', 'align}', 'center}', 'description}',
                \ 'document}', 'enumerate}', 'equation}', 'figure}',
                \ 'itemize}', 'table}', 'tabular}']

    call filter(lenv, 'v:val =~ "' . a:base . '"')

    call sort(lenv)
    let rr = []
    for env in lenv
        call add(rr, {'word': env})
    endfor
    return rr
endfunction


" Pointers to functions whose purposes are the same in rnoweb, rrst, rmd,
" rhelp and rdoc and which are called at common_global.vim
let b:IsInRCode = function("RnwIsInRCode")
let b:PreviousRChunk = function("RnwPreviousChunk")
let b:NextRChunk = function("RnwNextChunk")
let b:SendChunkToR = function("RnwSendChunkToR")

let b:rplugin_knitr_pattern = "^<<.*>>=$"

"==========================================================================
" Key bindings and menu items

call RCreateStartMaps()
call RCreateEditMaps()
call RCreateSendMaps()
call RControlMaps()
call RCreateMaps('nvi', 'RSetwd',        'rd', ':call RSetWD()')

" Only .Rnw files use these functions:
call RCreateMaps('nvi', 'RSweave',      'sw', ':call RWeave("nobib", 0, 0)')
call RCreateMaps('nvi', 'RMakePDF',     'sp', ':call RWeave("nobib", 0, 1)')
call RCreateMaps('nvi', 'RBibTeX',      'sb', ':call RWeave("bibtex", 0, 1)')
if has_key(g:Rcfg, "rm_knit_cache") && g:Rcfg.rm_knit_cache
    call RCreateMaps('nvi', 'RKnitRmCache', 'kr', ':call RKnitRmCache()')
endif
call RCreateMaps('nvi', 'RKnit',        'kn', ':call RWeave("nobib", 1, 0)')
call RCreateMaps('nvi', 'RMakePDFK',    'kp', ':call RWeave("nobib", 1, 1)')
call RCreateMaps('nvi', 'RBibTeXK',     'kb', ':call RWeave("bibtex", 1, 1)')
call RCreateMaps('nvi', 'RIndent',      'si', ':call RnwToggleIndentSty()')
call RCreateMaps('ni',  'RSendChunk',   'cc', ':call b:SendChunkToR("silent", "stay")')
call RCreateMaps('ni',  'RESendChunk',  'ce', ':call b:SendChunkToR("echo", "stay")')
call RCreateMaps('ni',  'RDSendChunk',  'cd', ':call b:SendChunkToR("silent", "down")')
call RCreateMaps('ni',  'REDSendChunk', 'ca', ':call b:SendChunkToR("echo", "down")')
call RCreateMaps('nvi', 'ROpenPDF',     'op', ':call ROpenPDF("Get Master")')
if g:Rcfg.synctex
    call RCreateMaps('ni', 'RSyncFor',  'gp', ':call SyncTeX_forward()')
    call RCreateMaps('ni', 'RGoToTeX',  'gt', ':call SyncTeX_forward(1)')
endif
call RCreateMaps('n', 'RNextRChunk',     'gn', ':call b:NextRChunk()')
call RCreateMaps('n', 'RPreviousRChunk', 'gN', ':call b:PreviousRChunk()')

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
