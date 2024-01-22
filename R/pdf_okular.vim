
function OkularJobStdout(job_id, data, etype)
    for cmd in a:data
        if cmd =~ "^call "
            exe cmd
        endif
    endfor
endfunction

function StartOkularNeovim(fullpath)
    let g:rplugin.jobs["Okular"] = jobstart(["okular", "--unique",
                \ "--editor-cmd", "echo 'call SyncTeX_backward(\"%f\",  \"%l\")'", a:fullpath],
                \ {"detach": 1, "on_stdout": function('OkularJobStdout')})
    if g:rplugin.jobs["Okular"] < 1
        call RWarningMsg("Failed to run Okular...")
    endif
endfunction

function ROpenPDF2(fullpath)
    call StartOkularNeovim(a:fullpath)
endfunction

function SyncTeX_forward2(tpath, ppath, texln, tryagain)
    let texname = substitute(a:tpath, ' ', '\\ ', 'g')
    let pdfname = substitute(a:ppath, ' ', '\\ ', 'g')
    let g:rplugin.jobs["OkularSyncTeX"] = jobstart(["okular", "--unique", 
                \ "--editor-cmd", "echo 'call SyncTeX_backward(\"%f\",  \"%l\")'",
                \ pdfname . "#src:" . a:texln . texname],
                \ {"detach": 1, "on_stdout": function('OkularJobStdout')})
    if g:rplugin.jobs["OkularSyncTeX"] < 1
        call RWarningMsg("Failed to run Okular (SyncTeX forward)...")
    endif
    if g:rplugin.has_awbt
        call RRaiseWindow(pdfname)
    endif
endfunction
