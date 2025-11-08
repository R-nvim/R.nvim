;; R-like Language Highlighting Queries (highlights.scm)
;; This file defines queries to target specific nodes in the AST for syntax highlighting.

;; 1. Highlight Constants
;; Targets the 'constant' rule which includes keywords like TRUE, FALSE, NULL, etc.
;; Use the standard @constant.builtin capture.
(routNormal) @rout_normal
; (routConst) @rout_contant
(routNumber) @rout_number
(routNegNum) @rout_negnum
(routTrue) @rout_true
(routFalse) @rout_false
(routInf) @rout_inf
