" Check whether Tmux is OK
if !executable('tmux')
    let g:Rcfg.external_term = 0
    call RWarningMsg("tmux executable not found")
    finish
endif

if system("uname") =~ "OpenBSD"
    " Tmux does not have -V option on OpenBSD: https://github.com/jcfaria/Vim-R-plugin/issues/200
    let s:tmuxversion = "0.0"
else
    let s:tmuxversion = system("tmux -V")
    let s:tmuxversion = substitute(s:tmuxversion, '.* \([0-9]\.[0-9]\).*', '\1', '')
    if strlen(s:tmuxversion) != 3
        let s:tmuxversion = "1.0"
    endif
    if s:tmuxversion < "3.0"
        call RWarningMsg("Nvim-R requires Tmux >= 3.0")
        let g:rplugin.failed = 1
        finish
    endif
endif
unlet s:tmuxversion

let g:rplugin.tmuxsname = "NvimR-" . substitute(localtime(), '.*\(...\)', '\1', '')

let g:Rcfg.setwidth = get(g:, 'R_setwidth', 2)

if !has_key(g:Rcfg, 'source') || (has_key(g:Rcfg, 'source') && g:Rcfg.source !~# 'tmux_split.vim')
    exe 'source ' . substitute(expand('<sfile>:h:h'), ' ', '\ ', 'g') . '/R/extern_term.vim'
endif

