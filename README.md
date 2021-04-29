# Archtail

Archtail is a Archlinux installer using whiptail.  It's supposed to be a simple Arch
installer for the masses.  But mainly it was an excuse for me to learn whiptail.

## Current Status

I'm new to whiptail, so I ran into a problem with the `--gauge` switch.  Apparently, if you
want to show a progress gauge, you have to find a way of outputting a number stream to STDOUT
that represents the progress of your process.  That capability is *not* built into `--gauge`
by default.  It's up to you to build that into your program.  How to do this?  Well, that's
what I'm currently experimenting with in my `whipsample.sh` program in
my [binfiles](https://github.com/deepbsd/binfiles) repo.

Currently the progress gauge works okay.  The installer works up to the Xorg-less part.
There are still two or three places where STDOUT gets displayed to the screen rather than to
the logfile.  Have to chase those down.  Also, I need to debug the X install functions.  They
are not fully working yet.
