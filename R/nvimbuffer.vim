" This file contains code used only when R run in a Neovim buffer

function SendCmdToR_Buffer(...)
    if g:rplugin.jobs["R"]
        if g:Rcfg.clear_line
            if g:Rcfg.editing_mode == "emacs"
                let cmd = "\001\013" . a:1
            else
                let cmd = "\x1b0Da" . a:1
            endif
        else
            let cmd = a:1
        endif

        " Update the width, if necessary
        try
            let bwid = bufwinid(g:rplugin.R_bufnr)
        catch /.*/
            let bwid = -1
        endtry
        if g:Rcfg.setwidth != 0 && g:Rcfg.setwidth != 2 && bwid != -1
            let rwnwdth = winwidth(bwid)
            if rwnwdth != s:R_width && rwnwdth != -1 && rwnwdth > 10 && rwnwdth < 999
                let s:R_width = rwnwdth
                let Rwidth = s:R_width + s:number_col
                if has("win32")
                    let cmd = "options(width=" . Rwidth . "); ". cmd
                else
                    call SendToNvimcom("E", "options(width=" . Rwidth . ")")
                    sleep 10m
                endif
            endif
        endif

        if g:Rcfg.auto_scroll && cmd !~ '^quit(' && bwid != -1
            call nvim_win_set_cursor(bwid, [nvim_buf_line_count(nvim_win_get_buf(bwid)), 0])
        endif

        if !(a:0 == 2 && a:2 == 0)
            let cmd = cmd . "\n"
        endif
        call chansend(g:rplugin.jobs["R"], cmd)
        return 1
    else
        call RWarningMsg("Is R running?")
        return 0
    endif
endfunction

function CloseRTerm()
    if has_key(g:rplugin, "R_bufnr")
        try
            " R migh have been killed by closing the terminal buffer with the :q command
            exe "sbuffer " . g:rplugin.R_bufnr
        catch /E94/
        endtry
        if g:Rcfg.close_term && g:rplugin.R_bufnr == bufnr("%")
            startinsert
            call feedkeys(' ')
        endif
        unlet g:rplugin.R_bufnr
    endif
endfunction

function SplitWindowToR()
    if g:Rcfg.rconsole_width > 0 && winwidth(0) > (g:Rcfg.rconsole_width + g:Rcfg.min_editor_width + 1 + (&number * &numberwidth))
        if g:Rcfg.rconsole_width > 16 && g:Rcfg.rconsole_width < (winwidth(0) - 17)
            silent exe "belowright " . g:Rcfg.rconsole_width . "vnew"
        else
            silent belowright vnew
        endif
    else
        if g:Rcfg.rconsole_height > 0 && g:Rcfg.rconsole_height < (winheight(0) - 1)
            silent exe "belowright " . g:Rcfg.rconsole_height . "new"
        else
            silent belowright new
        endif
    endif
endfunction

function ReOpenRWin()
    let wlist = nvim_list_wins()
    for wnr in wlist
        if nvim_win_get_buf(wnr) == g:rplugin.R_bufnr
            " The R buffer is visible
            return
        endif
    endfor
    let edbuf = bufname("%")
    call SplitWindowToR()
    call nvim_win_set_buf(0, g:rplugin.R_bufnr)
    exe "sbuffer " . edbuf
endfunction

function StartR_InBuffer()
    if string(g:SendCmdToR) != "function('SendCmdToR_fake')"
        call ReOpenRWin()
        return
    endif

    let g:SendCmdToR = function('SendCmdToR_NotYet')

    let edbuf = bufname("%")
    set switchbuf=useopen

    call SplitWindowToR()

    if has("win32")
        call SetRHome()
    endif
    let g:rplugin.jobs["R"] = termopen(g:rplugin.R . " " . join(g:rplugin.r_args), {'on_exit': function('ROnJobExit')})
    if has("win32")
        redraw
        call UnsetRHome()
    endif
    let g:rplugin.R_bufnr = bufnr("%")
    if g:Rcfg.esc_term
        tnoremap <buffer> <Esc> <C-\><C-n>
    endif
    for optn in split(g:Rcfg.buffer_opts)
        exe 'setlocal ' . optn
    endfor

    let s:R_width = 0
    if &number
        if g:Rcfg.setwidth < 0 && g:Rcfg.setwidth > -17
            let s:number_col = g:Rcfg.setwidth
        else
            let s:number_col = -6
        endif
    else
        let s:number_col = 0
    endif

    " Set b:pdf_is_open to avoid error when the user has to go to R Console to
    " deal with latex errors while compiling the pdf
    let b:pdf_is_open = 1
    exe "sbuffer " . edbuf
    stopinsert
    call WaitNvimcomStart()
endfunction
