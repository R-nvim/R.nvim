" Vim syntax file
" Language:	Object browser of R Workspace
" Maintainer:	Jakson Alves de Aquino (jalvesaq@gmail.com)

if !has("nvim")
    finish
endif
if exists("b:current_syntax")
    finish
endif
scriptencoding utf-8

setlocal iskeyword=@,48-57,_,.

setlocal conceallevel=2
setlocal concealcursor=nvc
syn match rbrowserNumeric	"n#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserCharacter	"t#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserFactor	"f#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserFunction	"F#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserControl 	"C#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserDF  	"d#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserList	"l#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserLogical	"b#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserLibrary	":#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserS4	"4#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserS7	"7#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserEnv	"e#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserLazy	"p#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserUnknown	"o#.*\t" contains=rbrowserDelim,rbrowserTab
syn match rbrowserNmSpace	"^.GlobalEnv "
syn match rbrowserNmSpace	"^Libraries "
syn match rbrowserLink		" Libraries$"
syn match rbrowserLink		" .GlobalEnv$"
syn match rbrowserTreePart	"├─"
syn match rbrowserTreePart	"└─"
syn match rbrowserTreePart	"│"
if &encoding != "utf-8"
    syn match rbrowserTreePart	"|"
    syn match rbrowserTreePart	"`-"
    syn match rbrowserTreePart	"|-"
endif

syn match rbrowserTab contained "\t"
syn match rbrowserLen " \[[0-9]\+, [0-9]\+\]$" contains=rbrowserEspSpc
syn match rbrowserLen " \[[0-9]\+\]$" contains=rbrowserEspSpc
syn match rbrowserErr /Error: label isn't "character"./
syn match rbrowserDelim contained /\S#/ conceal

hi def link rbrowserNmSpace	Title
hi def link rbrowserNumeric	Number
hi def link rbrowserCharacter	String
hi def link rbrowserFactor	Special
hi def link rbrowserDF  	Type
hi def link rbrowserList	StorageClass
hi def link rbrowserLibrary	PreProc
hi def link rbrowserLink	Comment
hi def link rbrowserLogical	Boolean
hi def link rbrowserFunction	Function
hi def link rbrowserControl 	Statement
hi def link rbrowserS4		Structure
hi def link rbrowserS7		Typedef
hi def link rbrowserEnv		Include
hi def link rbrowserLazy	Comment
hi def link rbrowserUnknown	Normal
hi def link rbrowserErr 	ErrorMsg
hi def link rbrowserTreePart	Comment
hi def link rbrowserDelim	Ignore
hi def link rbrowserTab		Ignore
hi def link rbrowserLen		Comment

" vim: ts=8 sw=4
