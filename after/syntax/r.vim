if exists("b:this_is_rout")
    exe "syn match rComment /^" . b:this_is_rout.prompt . ' /'
    exe "syn match rComment /^" . b:this_is_rout.cont . ' /'
endif
