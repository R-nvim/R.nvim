
function StartRStudio()
    if string(g:SendCmdToR) != "function('SendCmdToR_fake')"
        return
    endif

    let g:SendCmdToR = function('SendCmdToR_NotYet')

    if has("win32")
        call SetRHome()
    endif
    let g:rplugin.jobs["RStudio"] = StartJob([g:RStudio_cmd], {
                \ 'on_stderr': function('ROnJobStderr'),
                \ 'on_exit':   function('ROnJobExit'),
                \ 'detach': 1 })
    if has("win32")
        call UnsetRHome()
    endif

    call WaitNvimcomStart()
endfunction

function SendCmdToRStudio(...)
    if !IsJobRunning("RStudio")
        call RWarningMsg("Is RStudio running?")
        return 0
    endif
    let cmd = substitute(a:1, '"', '\\"', "g")
    call SendToNvimcom("E", 'sendToConsole("' . cmd . '", execute=TRUE)')
    return 1
endfunction

let g:Rcfg.bracketed_paste = 0
let g:Rcfg.parenblock = 0
