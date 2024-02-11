""" Functions for communication with R.nvim """
import sys

def rnvim_cmd(cmd):
    """ R.nvim executes the output of jobs """
    sys.stdout.write(cmd)
    sys.stdout.flush()

def rnvim_warn(wrn):
    """ R.nvim echoes as warning messages the output sent by jobs to stderr """
    sys.stderr.write(wrn)
    sys.stderr.flush()
