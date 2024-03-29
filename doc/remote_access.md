## Both Neovim and R on the remote machine

The easiest way to run R in a remote machine is to log into the remote device
through ssh, start Neovim, and run R in a Neovim's terminal (the default). You
will only need both Neovim and R configured as usual in the remote
machine.

## Only R on the remote machine

However, if you need to start Neovim on the local machine and
run R in the remote machine, then, a lot of additional configuration is
required to enable full communication between Neovim and R because by default
R.nvim only accepts TCP connections from the local host, and,
R saves temporary files in the `/tmp` directory of the machine where it is
running. To make the communication between local Neovim and remote R possible,
the remote R has to know the IP address of the local machine and one remote
directory must be mounted locally. Below is an example of how to achieve this
goal.

  1. Setup the remote machine to accept ssh login from the local machine
     without a password (search the command `ssh-copy-id` over the Internet to
     discover how to do it).

  2. Edit your `~/.Rprofile` on the remote machine (recommended):

       ```r
       options(nvimcom.verbose = 2)
       library(colorout)
       ```


  3. At the local machine:

     - Make the directory `~/.remoteR`:

       ```sh
       mkdir ~/.remoteR
       ```

     - Create the shell script `~/bin/mountR` with the following contents, and
       make it executable (of course, replace `remotelogin` and `remotehost`
       with valid values for your case):

       ```sh
       #!/bin/sh
       sshfs remotelogin@remotehost:/home/remotelogin/.cache/R.nvim ~/.remoteR
       ```

     - Create the shell script `~/bin/sshR` with the following contents, and
       make it executable (replace `remotelogin` and `remotehost` with the
       real values):

       ```sh
       #!/bin/sh

       LOCAL_MOUNT_POINT=$RNVIM_COMPLDIR
       REMOTE_CACHE_DIR=$RNVIM_REMOTE_COMPLDIR
       REMOTE_LOGIN_HOST=remotelogin@remotehost

       NVIM_IP_ADDRESS=$(hostname -I)
       REMOTE_DIR_IS_MOUNTED=$(df | grep $LOCAL_MOUNT_POINT)

       if [ "x$REMOTE_DIR_IS_MOUNTED" = "x" ]
       then
           echo "WARN: Remote directory '$REMOTE_CACHE_DIR' not mounted. Quit Neovim and start it again.\x14"
           sshfs $REMOTE_LOGIN_HOST:$REMOTE_CACHE_DIR $LOCAL_MOUNT_POINT
           sync
           exit 153
       fi

       if [ "x$RNVIM_PORT" = "x" ]
       then
           PSEUDOTERM='-T'
       else
           PSEUDOTERM='-t'
       fi

       ssh $PSEUDOTERM $REMOTE_LOGIN_HOST \
         "RNVIM_TMPDIR=$REMOTE_CACHE_DIR/tmp \
         RNVIM_COMPLDIR=$REMOTE_CACHE_DIR \
         RNVIM_ID=$RNVIM_ID \
         RNVIM_SECRET=$RNVIM_SECRET \
         R_DEFAULT_PACKAGES=$R_DEFAULT_PACKAGES \
         NVIM_IP_ADDRESS=$NVIM_IP_ADDRESS \
         RNVIM_PORT=$RNVIM_PORT R $*"
       ```

     - Add this to your R.nvim config:

       ```lua
       R_app = '/home/locallogin/bin/sshR'
       R_cmd = '/home/locallogin/bin/sshR'
       compldir = '/home/locallogin/.remoteR'
       remote_compldir = '/home/remotelogin/.cache/R.nvim'
       local_R_library_dir = '/path/to/local/R/library' -- where nvimcom is installed
       ```

     - Mount the remote directory:

       ```sh
       ~/bin/mountR
       ```

     - Start Neovim and start R. Nvimcom should be automatically
       installed on the remote machine.

     - If nvimcom is not automatically installed, you will have to
       manually build nvimcom, copy the source to the remote machine, access
       the remote machine, and install the package. Example:

       ```sh
       cd /tmp
       R CMD build /path/to/R.nvim/R/nvimcom
       scp nvimcom_0.9-149.tar.gz remotelogin@remotehost:/tmp
       ssh remotelogin@remotehost
       cd /tmp
       R CMD INSTALL nvimcom_0.9-149.tar.gz
       ```

## Alternative: vimcmdline

Running R on a remote machine will make a lot of data to be transferred
through a TCP connection between the R package `nvimcom` and the application
`rnvimserver` run by R.nvim. If your connection is not fast enough or its
latency is too high, you could consider using
[vimcmdline](https://github.com/jalvesaq/vimcmdline) or a similar plugin. Of
course, none of R.nvim's features that depend on information on R's workspace
will be available.

Below is an example for `init.lua` of how to configure _vimcmdline_ for
accessing R remotely:

```lua
vim.g.cmdline_app = {
    r = 'ssh -t user@remote-machine R --no-save',
}
```

Most of R.nvim's key bindings call functions that send code to R, and, because they
will not be used, it is better to disable them:

```lua
vim.g.R_user_maps_only = 1
```

Finally, you may want to enable custom actions in _vimcmdline_ (seek `cmdline_actions`
at [doc/vimcmdline.txt](https://github.com/jalvesaq/vimcmdline/blob/master/doc/vimcmdline.txt)).
