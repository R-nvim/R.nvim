package tree_sitter_rout_test

import (
	"testing"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_rout "github.com/r-nvim/tree-sitter-rout/bindings/go"
)

func TestCanLoadGrammar(t *testing.T) {
	language := tree_sitter.NewLanguage(tree_sitter_rout.Language())
	if language == nil {
		t.Errorf("Error loading Rout grammar")
	}
}
