# Archtail

Archtail is a Archlinux installer using whiptail.  It's supposed to be a simple Arch
installer for the masses.  But mainly it was an excuse for me to learn whiptail.

To use this script, issue this command from your freshly booted archiso image:
```
curl -O https://raw.githubusercontent.com/deepbsd/Archtail/master/archtail.sh
```

It will be best if you use three different tty's.  Open the script in your editor on tty1
and run the script ( `bash archtail.sh` ) on tty2.  On tty3 you can watch the installation
progress by tailing the install log: `tail -f /tmp/install.log`

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

## Sunday, May 2 2021

The script works.  You'll wind up with a freshly installed Archlinux system if you don't
make any mistakes.

Unfortunately, it's probably still possible (maybe even easy?) to type some wrong things
and end up with a broken system.  I'll still need to build in some more resiliency.

Another idea I've been working on is to build a configuration file with either a
whiptail script or dynamically.  Then have that config file get used to automatically
install an Arch system.  That process might be duplicated by a process across any number
of containers, for example.  I'd like to try that.

Anyway, I'm glad to say it works.  All the features except cryptsetup.  Everything else.
Yaaay!

## Friday, May 21, 2021

I've done a fair amount of work on the script.  lv\_create now calls external scripts.  Also
we're giving the user the chance to install a non-us keyboard keymap.  

## TODO

Eventually, I'll need to break this sucker up into separate files, and at that
point you'll have to clone it into the Archiso instance.  That's fine.  I'd prefer
to have kept it simple, but it's just gotten too big.

There are some other things that have struck me though:

1. Break some of the larger functions into smaller functions.  Particularly
   lv\_create.  That one is too big.  UPDATE: Haven't done this, but I have re-
   organized the sequence of the functions into Utility functions, Disk functions,
   Installation functions, and Other functions.  These could later be broken out 
   into separate files. NOTE: lv\_create now calls external functions.  But it's still
   pretty big.

2. (DONE) I want to have a list of all executables in the script and at the start of the
   script make sure they are all in the $PATH (or at least are all executable).
   UPDATE: This currently works now, but the extra repo is not active by default.  
   Still looking into that.

3. (DONE) The user should be able to determine his/her own desktop environment or window
   manager.  Right now they're getting Cinnamon and lightdm whether they want it or
   not.  UPDATE:  This currently is how the script works.  The default is still Cinnamon
   with lightdm, however.  But whatever the user selects will become the default environment.

4. I don't need to ask for whether to do LVM or not.  I should probably just get
   the user's choice of disk for installation by default and install my usual LVM
   to it using ext4.  I can build in whether it chooses GPT or MBR disk labels.
   Not sure on this.  I could just survey the top Linux installers and see what
   they do. 

5. (DONE) Is there a way to re-use the same functions for creating LVs and regular
   partitions?  Seems like there should be, but I should find out.
   UPDATE:  If I decide to do away with non-LVM disk prep, that will remove
   quite a few functions.

6. Cryptsetup:  Do I want to bother with it or not?  (Still haven't worked on this again.)

7. (DONE) Use a checkmark to indicate the item is complete on the main menu.
   UPDATE: Creating an actual checkmark on a TTY is actually more trouble than it's worth,
   so I just created an 'X' in a box in front of each startmenu pick item.

8. I should also check that archtail is being called by BASH and not zsh, for
   example.  (Have not addressed this yet.)
 

