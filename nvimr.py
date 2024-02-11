""" Functions for communication with R-Nvim """
import sys

def nvimr_cmd(cmd):
    """ R-Nvim executes the output of jobs """
    sys.stdout.write(cmd)
    sys.stdout.flush()

def nvimr_warn(wrn):
    """ R-Nvim echoes as warning messages the output sent by jobs to stderr """
    sys.stderr.write(wrn)
    sys.stderr.flush()
