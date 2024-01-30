"==============================================================================
" Functions that might be called even before R is started.
"
" The functions and variables defined here are common for all buffers of all
" file types supported by R-Nvim and must be defined only once.
"==============================================================================


set encoding=utf-8
scriptencoding utf-8

" Do this only once
if exists("s:did_global_stuff")
    finish
endif
let s:did_global_stuff = 1


"==============================================================================
" Check if there is more than one copy of R-Nvim
" (e.g. from the Vimballl and from a plugin manager)
"==============================================================================

if exists("*RWarningMsg")
    " A common_global.vim script was sourced from another version of NvimR.
    finish
endif

function UpdateLocalFunctions(...)
    " avoid nvimrclient error until incorporating code from @she3o
endfunction

"==============================================================================
" WarningMsg
"==============================================================================

function RWarningMsg(wmsg)
    exe 'lua require("r").warn("' . a:wmsg . '")'
endfunction


"==============================================================================
" Check Vim/Neovim version
"==============================================================================

if !has("nvim-0.6.0")
    call RWarningMsg("R-Nvim requires Neovim >= 0.6.0.")
    let g:rplugin.failed = 1
    finish
endif

" Convert <M--> into <-
function RAssign()
    lua require("r.edit").assign()
endfunction

" Get the word either under or after the cursor.
" Works for word(| where | is the cursor position.
function RGetKeyword()
    " Go back some columns if character under cursor is not valid
    let line = getline(".")
    let i = col(".") - 1
    if strlen(line) == 0
        return ""
    endif
    " line index starts in 0; cursor index starts in 1:
    " Skip opening braces
    while i > 0 && line[i] =~ '(\|\[\|{'
        let i -= 1
    endwhile
    " Go to the beginning of the word
    " See https://en.wikipedia.org/wiki/UTF-8#Codepage_layout
    while i > 0 && line[i-1] =~ '\k\|@\|\$\|\:\|_\|\.' || (line[i-1] > "\x80" && line[i-1] < "\xf5")
        let i -= 1
    endwhile
    " Go to the end of the word
    let j = i
    while line[j] =~ '\k\|@\|\$\|\:\|_\|\.' || (line[j] > "\x80" && line[j] < "\xf5")
        let j += 1
    endwhile
    let rkeyword = strpart(line, i, j - i)
    return rkeyword
endfunction

" Get the name of the first object after the opening parenthesis. Useful to
" call a specific print, summary, ..., method instead of the generic one.
function RGetFirstObj(rkeyword, ...)
    let firstobj = ""
    if a:0 == 3
        let line = substitute(a:1, '#.*', '', "")
        let begin = a:2
        let listdf = a:3
    else
        let line = substitute(getline("."), '#.*', '', "")
        let begin = col(".")
        let listdf = v:false
    endif
    if strlen(line) > begin
        let piece = strpart(line, begin)
        while piece !~ '^' . a:rkeyword && begin >= 0
            let begin -= 1
            let piece = strpart(line, begin)
        endwhile

        " check if the first argument is being passed through a pipe operator
        if begin > 2
            let part1 = strpart(line, 0, begin)
            if part1 =~ '\k\+\s*\(|>\|%>%\)'
                let pipeobj = substitute(part1, '.\{-}\(\k\+\)\s*\(|>\|%>%\)\s*', '\1', '')
                return [pipeobj, v:true]
            endif
        endif
        let pline = substitute(getline(line('.') - 1), '#.*$', '', '')
        if pline =~ '\k\+\s*\(|>\|%>%\)\s*$'
            let pipeobj = substitute(pline, '.\{-}\(\k\+\)\s*\(|>\|%>%\)\s*$', '\1', '')
            return [pipeobj, v:true]
        endif

        let line = piece
        if line !~ '^\k*\s*('
            return [firstobj, v:false]
        endif
        let begin = 1
        let linelen = strlen(line)
        while line[begin] != '(' && begin < linelen
            let begin += 1
        endwhile
        let begin += 1
        let line = strpart(line, begin)
        let line = substitute(line, '^\s*', '', "")
        if (line =~ '^\k*\s*(' || line =~ '^\k*\s*=\s*\k*\s*(') && line !~ '[.*('
            let idx = 0
            while line[idx] != '('
                let idx += 1
            endwhile
            let idx += 1
            let nparen = 1
            let len = strlen(line)
            let lnum = line(".")
            while nparen != 0
                if idx == len
                    let lnum += 1
                    while lnum <= line("$") && strlen(substitute(getline(lnum), '#.*', '', "")) == 0
                        let lnum += 1
                    endwhile
                    if lnum > line("$")
                        return ["", v:false]
                    endif
                    let line = line . substitute(getline(lnum), '#.*', '', "")
                    let len = strlen(line)
                endif
                if line[idx] == '('
                    let nparen += 1
                else
                    if line[idx] == ')'
                        let nparen -= 1
                    endif
                endif
                let idx += 1
            endwhile
            let firstobj = strpart(line, 0, idx)
        elseif line =~ '^\(\k\|\$\)*\s*[' || line =~ '^\(k\|\$\)*\s*=\s*\(\k\|\$\)*\s*[.*('
            let idx = 0
            while line[idx] != '['
                let idx += 1
            endwhile
            let idx += 1
            let nparen = 1
            let len = strlen(line)
            let lnum = line(".")
            while nparen != 0
                if idx == len
                    let lnum += 1
                    while lnum <= line("$") && strlen(substitute(getline(lnum), '#.*', '', "")) == 0
                        let lnum += 1
                    endwhile
                    if lnum > line("$")
                        return ["", v:false]
                    endif
                    let line = line . substitute(getline(lnum), '#.*', '', "")
                    let len = strlen(line)
                endif
                if line[idx] == '['
                    let nparen += 1
                else
                    if line[idx] == ']'
                        let nparen -= 1
                    endif
                endif
                let idx += 1
            endwhile
            let firstobj = strpart(line, 0, idx)
        else
            let firstobj = substitute(line, ').*', '', "")
            let firstobj = substitute(firstobj, ',.*', '', "")
            let firstobj = substitute(firstobj, ' .*', '', "")
        endif
    endif

    if firstobj =~ "="
        let firstobj = ""
    endif

    if firstobj[0] == '"' || firstobj[0] == "'"
        let firstobj = "#c#"
    elseif firstobj[0] >= "0" && firstobj[0] <= "9"
        let firstobj = "#n#"
    endif


    if firstobj =~ '"'
        let firstobj = substitute(firstobj, '"', '\\"', "g")
    endif

    return [firstobj, v:false]
endfunction

function ROpenPDF(fullpath)
    exe 'lua require("r.pdf").open("' . a:fullpath . '")'
endfunction

function RCreateMaps(type, plug, combo, target)
    exe 'lua require("r.maps").create("' . a:type . '", "' . a:plug . '", "' .  a:combo . '" , "' .  substitute(a:target, '"', '\\"', 'g') . '")'
endfunction

function RControlMaps()
    lua require("r.maps").control()
endfunction

function RCreateStartMaps()
    lua require("r.maps").start()
endfunction

function RCreateEditMaps()
    lua require("r.maps").edit()
endfunction

function RCreateSendMaps()
    lua require("r.maps").send()
endfunction

function RBufEnter()
    lua require("r.edit").buf_enter()
endfunction

" Store list of files to be deleted on VimLeave
function AddForDeletion(fname)
    exe 'lua require("r.edit").add_for_deletion("' . a:fname . '")'
endfunction

function ShowBuildOmnilsError(stt)
    exe 'lua require("r.nrs").show_bol_error(' . a:stt .')'
endfunction

function UpdateSynRhlist()
    exe 'lua require("r.nrs").update_Rhelp_list()'
endfunction

" Callback function
function EchoNCSInfo(info)
    exe 'lua require("r.nrs").echo_nrs_info(' . a:info .')'
endfunction

function JobStdin(key, cmd)
    exe 'lua require("r.nrs").echo_nrs_info("' . a:key . '", "' . a:cmd . '")'
endfunction

" Function to send commands
" return 0 on failure and 1 on success
function SendCmdToR_fake(...)
    call RWarningMsg("Did you already start R?")
    return 0
endfunction

function StartR(whatr)
    let g:rnvim_status = 3
    let Rcfg = luaeval('require("r.config").get_config()')
    if !exists("*ReallyStartR")
        exe "source " . substitute(Rcfg.rnvim_home, " ", "\\ ", "g") . "/R/start_r.vim"
    endif
    exe 'lua require("r.run").really_start_R("' . a:whatr . '")'
endfunction

function AutoStartR(...)
    if string(g:SendCmdToR) != "function('SendCmdToR_fake')"
        return
    endif
    if v:vim_did_enter == 0 || g:R_Nvim_status < 3
        call timer_start(100, 'AutoStartR')
        return
    endif
    call StartR("R")
endfunction

command -nargs=1 -complete=customlist,RLisObjs Rinsert :call RInsert(<q-args>, "here")
command -range=% Rformat <line1>,<line2>:call RFormatCode()
command RBuildTags :call RBuildTags()
command -nargs=? -complete=customlist,RLisObjs Rhelp :call RAskHelp(<q-args>)
command -nargs=? -complete=dir RSourceDir :call RSourceDirectory(<q-args>)
command RStop :call SignalToR('SIGINT')
command RKill :call SignalToR('SIGKILL')
command -nargs=? RSend :call g:SendCmdToR(<q-args>)
command RDebugInfo :lua require("r.edit").show_debug_info()

"==============================================================================
" Temporary links to be deleted when start_r.vim is sourced

