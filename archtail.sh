#!/usr/bin/env bash


################################
###    GLOBAL VARIABLES  #######
################################

# NOTE:  Many of these variables get set programmatically as you run the program.
# But they must be declared in the global namespace so they can be updated in local
# functions.  Here in Archtail, they get updated many times as you run the individual
# functions, such as lv_create() and so forth.

# VERIFY BOOT MODE
#  This is not a variable but a function that determines how the program will
#  branch in its disktable.
efi_boot_mode(){
    # if the efivars directory exists we definitely have an EFI BIOS
    # otherwise, we could have a non-standard EFI or even an MBR-only system
    ( $(ls /sys/firmware/efi/efivars &>/dev/null) && return 0 ) || return 1
}

LOGFILE='/tmp/install.log'

# CHECK IF UEFI BIOS OR NOT AND DISKLABEL
if $(efi_boot_mode); then 
    DISKTABLE='GPT'
else
    DISKTABLE='MBR'
fi

# PUT THESE IN GLOBAL NAMESPACE
IN_DEVICE=''
EFI_SLICE=''
ROOT_SLICE=''
HOME_SLICE=''
SWAP_SLICE=''

# DEFAULT GRAPHICS DRIVERS ETC   ---  change as needed via whiptail later in script ---
wifi_drivers=(broadcom-wl-dkms iwd)   # find chipset for YOUR wifi card!
graphics_driver=(xf86-video-vmware)   # $( pacman -Ss xf86-video- ) will list available drivers...
display_mgr=(lightdm)                 # lightdm goes well with cinnamon desktop
mydesktop=( "${cinnamon_desktop[@]}" )

# VOL GROUP VARIABLES
USE_LVM=''   # gets set programmatically
USE_CRYPT='' # gets set programmatically
CRYPT_PART="arch_crypt"   # encrypted volume group for cryptsetup
VOL_GROUP="arch_vg"
LV_ROOT="ArchRoot"
LV_HOME="ArchHome"
LV_SWAP="ArchSwap"

# PARTITION SIZES  (You can edit these if desired)
BOOT_SIZE=512M     # BOOT applies to non-efi BIOS and MBR disklable
EFI_SIZE=512M      # EFI applies to GPT disklable
ROOT_SIZE=15G      # Applies to either root partition or root logical volume
SWAP_SIZE=4G       # calculate this with SWAP_SIZE="$(free | awk '/^Mem/ {mem=$2/1000000; print int(2.2*mem)}')G"
HOME_SIZE=''       # Takes up rest of drive

# You can edit this if you want
# For some reason the ubuntu geoip server doesn't always work
TIMEZONE='America/New_York'
LOCALE="en_US.UTF-8"
KEYBOARD="us"
# Perhaps I will use this to determine a user's locale setting; I don't use it right now.
EXT_IP=$( dig +short myip.opendns.com @resolver1.opendns.com )



##############################################
########     SOFTWARE SETS    ################
##############################################

# Contents of arrays are archlinux package names.  Sometimes these change. 
# The validate_pkgs function is supposed to check whether pkg names have dropped
# out or have changed.

# these are all executables in script that should be in $PATH
executables=( "date" "whiptail" "rm" "echo" "ls" "sed" "grep" "sleep" "exit" "shuf" "eval" \
"dig" "wget" "break" "timedatectl" "pgrep" "arch-chroot" "sgdisk" "sfdisk" "mkfs" "pvcreate" \
"vgcreate" "lvcreate" "mkswap" "swapon" "modprobe" "vgchange" "mount" "mkdir" "lsblk" \
"local" "if" "then" "for" "[[" "case" "genfstab" "locale-gen" "cat" "pacman" "passwd" \
"useradd" "systemctl" "declare" "while")

# replace with linux-lts or -zen if preferrable
base_system=( base base-devel linux linux-headers dkms linux-firmware vim sudo bash-completion )

base_essentials=(git mlocate pacman-contrib archlinux-keyring man-db man-pages)

network_essentials=( iwd dhcpcd openssh networkmanager )

my_services=( dhcpcd sshd NetworkManager systemd-homed )

basic_x=( xorg-server xorg-xinit mesa xorg-twm xterm gnome-terminal xorg-xclock xfce4-terminal firefox neofetch screenfetch lightdm-gtk-greeter )

extra_x1=( gkrellm powerline powerline-fonts powerline-vim adobe-source-code-pro-fonts cantarell-fonts gnu-free-fonts ) 

extra_x2=( noto-fonts breeze-gtk breeze-icons gtk-engine-murrine oxygen-icons xcursor-themes adapta-gtk-theme )

extra_x3=( arc-gtk-theme elementary-icon-theme gnome-icon-theme-extras arc-icon-theme lightdm-webkit-theme-litarvan mate-icon-theme ) 

extra_x4=( materia-gtk-theme papirus-icon-theme archlinux-wallpaper deepin-community-wallpapers deepin-wallpapers elementary-wallpapers )

cinnamon_desktop=( cinnamon nemo-fileroller )

#####  Include these desktops in 'all_extras' array if desired
xfce_desktop=( xfce4 xfce4-goodies )

mate_desktop=( mate mate-extra )

gnome_desktop=( gnome gnome-extra )

i3gaps_desktop=( i3-gaps dmenu feh rofi i3status i3blocks nitrogen i3status ttf-font-awesome ttf-ionicons )

qtile_desktop=( qtile dmenu feh rofi nitrogen ttf-font-awesome ttf-ionicons "${multimedia_stuff[@]}" )

xmonad_desktop=( xmonad xmonad-contrib )

awesome_desktop=( awesome vicious )

kde_desktop=( plasma plasma-wayland-session kde-applications plasma-workspace-wallpapers )

## Python3 should be installed by default
devel_stuff=( git nodejs npm npm-check-updates ruby )

printing_stuff=( system-config-printer foomatic-db foomatic-db-engine gutenprint cups cups-pdf cups-filters cups-pk-helper ghostscript gsfonts )

multimedia_stuff=( brasero sox eog shotwell imagemagick sox cmus mpg123 alsa-utils cheese )

all_extras=( "${kde_desktop[@]}" "${xmonad_desktop[@]}" "${qtile_desktop[@]}" "${xfce_desktop[@]}" "${i3gaps_desktop[@]}" "${mate_desktop[@]}" "${devel_stuff[@]}" "${printing_stuff[@]}" "${multimedia_stuff[@]}" )

##  fonts_themes=()    #  in case I want to break these out from extra_x

# This will exclude services because they are often named differently and are duplicates
all_pkgs=( base_system base_essentials network_essentials basic_x extra_x1 extra_x2 extra_x3 extra_x4 cinnamon_desktop xfce_desktop mate_desktop i3gaps_desktop devel_stuff printing_stuff multimedia_stuff qtile_desktop kde_desktop )

# Can't show checkmarks very easily...  This array will help show the user which tasks are completed or not
completed_tasks=( "X" )


##################################
###    FUNCTIONS    ##############
##################################
 
############  UTILITY FUNCTIONS  ####################

welcome(){
    message="Dave's ARCH Installer will lead you through a menu-driven process to\
        create a base installation of Archlinux on your computer or virtual machine\
        by selecting a group of tasks from a main menu.  "

    whiptail --backtitle "Dave's ARCH Installer (DARCHI)" --title "Welcome to DARCHI!" \
        --msgbox "$message" 15 80 

    # Remove old logfiles and start the new one
    [[ -f $LOGFILE ]] && rm $LOGFILE
    when=$(date)
    echo "=== START INSTALL: $when ===" &>>$LOGFILE
}

# AUTO SET TIMEZONE
auto_tz(){
    # Try to get the Timezone via wget.  If that fails, default to America/New_York
    pacman -Sy  &>>$LOGFILE 
    pacman -S wget --noconfirm &>>$LOGFILE

    # Check that service is up first...
    server='http://geoip.ubuntu.com/lookup'
    if $( ping -c3 "$server" 2>/dev/null ); then
        TIMEZONE=$(wget -O - -q http://geoip.ubuntu.com/lookup | sed -n -e 's/.*<TimeZone>\(.*\)<\/TimeZone>.*/\1/p')
    fi

    # Default TZ is America/New_York  (use auto_tz value if geoip site is up)
    TIMEZONE=${TIMEZONE:='America/New_York'}

    echo "***   auto_tz() says TIMEZONE is $TIMEZONE   ***"  &>>$LOGFILE

}

change_tz(){
    # Offer user chance to select a new tz in case wget didn't work properly
    backmessage="CHANGE TZ?"; message="Want to change TZ from $TIMEZONE?"
    # whiptail --yesno dialog
    if $(whiptail --backtitle "$backmessage" --title "$message" --yesno \
        "Keep timezone of $TIMEZONE?" --yes-button "Keep $TIMEZONE" \
        --no-button "Change timezone" 10 70 3>&1 1>&2 2>&3); then

        timezone=${TIMEZONE}
    
    else

        timezones=()
        # populate array with possible TZ's
        for timezone in $(timedatectl list-timezones); do
            timezones+=( $(printf "%s\t\t%s\n" $timezone 'timezone') )
        done

        backmessage="CHOOSE YOUR TIMEZONE"
        message="Please choose your timezone"

        # Let user pick the timezone
        timezone=$(eval `resize`; whiptail --backtitle "$backmessage" --title "$message" \
            --menu "Here are your timezones:" $LINES $COLUMNS $(( $LINES - 8 )) \
            "${timezones[@]}"  3>&1 1>&2 2>&3)
    fi

    # default to $TIMEZONE variable from auto_tz if the user cancels the previous form
    TIMEZONE=${timezone:=TIMEZONE}
}

change_kb(){
    # get a list of all keyboard files on the system
    keymaps=$(find /usr/share/kbd/keymaps/ -type f -printf "%f\n" | sort -V)
    # get the list into an array
    keymaps=( $keymaps )

    # status will be part of the menu list of kbd choices
    status=""
    # these will be menu options
    options=()

    # only turn on us keymap for default
    # Turns out I chose a --menu for whiptail and not a --radiolist
    # but I keep this around in case I want to go back to a --radiolist
    for file in "${keymaps[@]}"; do
        if [[ "${file%%.*}" == 'us' ]]; then
            status="ON"
        else
            status="OFF"
        fi

        # remove the suffix for the loadkeys command
        newfile=$( echo $file | sed 's/.map.gz//g' )
        # set up the line for the whiptail menu
        options+=( $( printf "%s\t\t%s" $newfile "=====" ) )
    done

    # Ask the user if he/she wants to keep a us keymap
    if (whiptail --backtitle "US KEYMAP?" --title "Do you want a US Keymap?" \
        --yesno "Keep a US keyboard keymap?" 10 80) ; then
        # Set default value for us in case setxkbmap doesn't work
        KEYBOARD=${KEYBOARD:='us'}
    else
        # if not, there are about 260 other options...
        KEYBOARD=$(eval resize; whiptail --backtitle "CHOOSE KEYBOARD" --title "Choose Your Keyboard" \
            --menu "Default keymap is US"  $LINES $COLUMNS $(( $LINES - 8 )) "${options[@]}" 3>&1 1>&2 2>&3 )
        # set default kb map to be us, incase above doesn't get set properly or user cancels
        KEYBOARD=${KEYBOARD:='us'}
    fi

    echo "==> Using $KEYBOARD keyboard keymap..." &>>$LOGFILE

    # Default value is 'us'; therefore load new value if we're not in US
    # loadkeys is not persistent.  Only loads for current session
    if [[ ! $KEYBOARD =~ 'us' ]] ; then loadkeys $KEYBOARD ; fi
}

# FIND GRAPHICS CARD
find_card(){
    card=$(lspci | grep VGA | sed 's/^.*: //g')

    whiptail --title "Your Video Card" --msgbox \
       "You're using a $card  Write this down and hit OK to continue." 8 65 3>&1 1>&2 2>&3
}

# IF NOT CONNTECTED
not_connected(){
    
    message="No network connection!!!  Perhaps your wifi card is not supported?\nIs your network card plugged in?"

    TERM=ansi whiptail --backtitle "NO NETWORK CONNECTION" \
        --title "Are you connected?" --infobox "$message" 15 70
    sleep 5
    exit 1
}

# ARE WE CONNTECTED??
check_connect(){
    TERM=ansi whiptail --backtitle "Checking Network Connection" \
        --title "Are you connected?" --infobox "Checking connection now..." 15 60 

    if $(ping -c 3 archlinux.org &>/dev/null); then

        TERM=ansi whiptail --backtitle "Network is UP" --title "Network is up!" \
           --infobox "Your network connection is up!" 15 60

        sleep 3
    else
        not_connected
    fi
}

# NOTE:  Showing a progress gauge in whiptail is a pain.  I do it by 
# passing the name of the process to measure (a function name) to a
# calling function.  The calling function calls the function and sends
# it to the background, and then immediately captures its PID.  
# We check for that PID and keep showing the progress meter if its still
# in the PID table.  If it drops out of the PID table, then we immediately
# show 98 99 100 pct progress with a 3 second wait between each.
# If the process is taking a very long time, we show 97pct 98pct 97pct 
# 98pct until the PID drops out of the PID table.  This way the user
# never suspects the install has frozen, just that he's going spastic.


# FOR SHOWING PROGRESS GAUGE FOR WHIPTAIL (this does the counting)
showprogress(){
    # start count, end count, shortest sleep, longest sleep
    start=$1; end=$2; shortest=$3; longest=$4

    for n in $(seq $start $end); do
        echo $n
        pause=$(shuf -i ${shortest:=1}-${longest:=3} -n 1)  # random wait between 1 and 3 seconds
        sleep $pause
    done
}

# CALL FOR SHOWING PROGRESS GAUGE (this calls the function)
specialprogressgauge(){
    process_to_measure=$1   # This is the function we're going to measure progress for
    message=$2              # Message on Whiptail progress window
    backmessage=$3          # Message on Background Window
    eval $process_to_measure &      # Start the process in the background
    thepid=$!               # Immediately capture the PID for this process
    echo "=== Watching PID $thepid for progress ===" &>>$LOGFILE
    num=10                  # Shortest progress bar could be 10 sec to 30 sec
    while true; do
        showprogress 1 $num 1 3 
        sleep 2             # Max of 47 sec before we check for completion
        while $(ps aux | grep -v 'grep' | grep "$thepid" &>/dev/null); do
            if [[ $num -gt 97 ]] ; then num=$(( num-1 )); fi
            showprogress $num $((num+1)) 
            num=$(( num+1 ))
        done
        showprogress 99 100 3 3  # If we have completion, we add 6 sec. Max of 53 sec.
        echo "=== No longer watching PID: $thepid ===" &>>$LOGFILE
        break
    done  | whiptail --backtitle "$backmessage" --title "Progress Gauge" --gauge "$message" 9 70 0
}

# UPDATE SYSTEM CLOCK
time_date(){
    timedatectl set-ntp true >"$LOGFILE" 2>&1
    time_date_status=$(timedatectl status)
    whiptail --backtitle "Timedate Status" --title "Time and Date Status" \
        --msgbox "$time_date_status" 10 70
}

# CHECK IF TASK IS COMPLETED
check_tasks(){

    # If task already exists in array return falsy
    # Function takes a task number as an argument
    # This function might not be needed anymore: STATUS TBD

    # just return an 'X' in the array position of the passed integer parameter
    completed_tasks[$1]="X"
}

# FIND CLOSEST MIRROR
check_reflector(){
    # Archlinux tries to find and work with the closest mirrors before installing.  This function 
    # tries to check whether that process is complete or not.
    
    whiptail --backtitle "REFLECTOR RUNNING" --title "Finding closest mirror" --infobox \
    "Evaluating and finding closest mirrors for Arch repos. This may take a while, but you'll be returned to the main menu as soon as possible." 10 65
    
    while true; do
        pgrep -x reflector &>/dev/null || break
        sleep 2
    done 
}

# FOR MKINITCPIO.IMG
lvm_hooks(){
    # this change makes sure to add lvm2 hook even when modules or hooks change names (as long as there is a
    # filesystems hook)
    sed -i 's/^\(HOOKS=["(]base .*\) filesystems \(.*\)$/\1 lvm2 filesystems \2/g' /mnt/etc/mkinitcpio.conf

    # sed -i 's/^HOOKS=(base udev autodetect modconf kms keyboard keymap block filesystems fsck)$/HOOKS=(base udev autodetect modconf modconf kms keyboard keymap block lvm2 filesystems fsck)/g' /mnt/etc/mkinitcpio.conf
    arch-chroot /mnt mkinitcpio -P 
}

encrypt_lvm_hook(){
#    sed -i 's/^HOOKS=(base udev autodetect modconf kms keyboard keymap block filesystems fsck)$/HOOKS=(base udev autodetect modconf kms keyboard keymap block lvm2 filesystems keyboard fsck)/g' /mnt/etc/mkinitcpio.conf
    sed -i 's/^\(HOOKS=["(]base .*\) filesystems \(.*\)$/\1 encrypt lvm2 filesystems \2/g' /mnt/etc/mkinitcpio.conf
    arch-chroot /mnt mkinitcpio -P 

}


# VALIDATE PKG NAMES IN SCRIPT
validate_pkgs(){

    MISSING_LOG=/tmp/missing_pkgs

    [[ -f $MISSING_LOG ]] && rm "$MISSING_LOG"

    message="Archlinux can change package names without notice. Just making sure we're okay.  We'll be right back with a list of any changes, if any. "

    TERM=ansi whiptail --backtitle "CHECKING PKG NAME CHANGES" --title \
        "Checking for pkg name changes" --infobox "$message" 8 80

    missing_pkgs=()

    echo -e "\n=== MISSING PKG NAMES (IF ANY) ===\n\n" &>>$MISSING_LOG
    
    # initialize the package database
    pacman -Sy   &>>$MISSING_LOG

    for pkg_arr in "${all_pkgs[@]}"; do

        declare -n arr_name=$pkg_arr  # make a namespace for each pkg_array

        for pkg_name in "${arr_name[@]}"; do
            if $( pacman -Sp $pkg_name &>/dev/null ); then
                echo -n "." &>>$MISSING_LOG
            else 
                echo -e "\n$pkg_name from $pkg_arr had an error...\n" >>$MISSING_LOG 2>&1
                missing_pkgs+=("$pkg_arr::$pkg_name")
            fi
        done
    done
    echo -e "\n\n=== END OF MISSING PKGS ===\n" &>>$MISSING_LOG
    
    whiptail --backtitle "Packages not in repos" --title \
       "These packages not in repos" --textbox $MISSING_LOG --scrolltext 20 80
}

# CHECK THAT ALL EXECUTABLES ARE AVAILABLE FOR THIS SCRIPT
checkpath(){
    echo "=== MISSING EXECUTABLES: ===" &>>$LOGFILE
    echo "${#executables[@]} executables being checked. Good if none are found!" &>>$LOGFILE
    for ex in "${executables[@]}"; do
        $( command -v $ex &>/dev/null) || ( echo $ex &>>$LOGFILE )
    done
    echo "== END MISSING EXECUTABLES ===" &>>$LOGFILE
}

# DISPLAY /MNT/ETC/HOSTS
show_hosts(){
    whiptail --backtitle "/ETC/HOSTS" --title "Your /etc/hosts file" --textbox /etc/hosts 25 80 
}

# SHOW ERROR IF FUNCTION DIDN'T SUCCEED, USER MAY EXIT OR NOT
show_error(){
    message=$1
    whiptail --backtitle "ERROR! ERROR!" --title "Error: " --msgbox "$message" 20 80
    whiptail --backtitle "QUIT OR CONTINUE" --title "Quit or Continue?" --yesno \
        --yes-button "Return to startmenu" --no-button "Exit DARCHI"
    ( [[ $? -eq 0 ]] && startmenu ) || exit 1
}



#################  DISK FUNCTIONS  ########################

# SELECT INSTALLATION DISK
choose_disk(){
       depth=$(lsblk | grep 'disk' | wc -l)
       local DISKS=()
       for d in $(lsblk | grep disk | awk '{printf "%s\n%s \\\n",$1,$4}'); do
            DISKS+=("$d")
       done

       whiptail --title "CHOOSE AN INSTALLATION DISK" \
           --radiolist " Your Installation Disk: " 20 70 "$depth" \
           "${DISKS[@]}" 3>&1 1>&2 2>&3
}

# INSTALL TO WHAT DEVICE?
get_install_device(){
    device=$(choose_disk)
    part_disk "$device"
}

# FOR LOGICAL VOLUME PARTITIONS
lv_create(){

    # Choose your installation device
    disk=$(choose_disk)
    IN_DEVICE=/dev/"$disk"
    choices=()

    # Set up the partition choices for the install disk
    if [[ $disk =~ 'nvme' ]]; then
        choices+=( "${disk}p1" "${disk}p2" "${disk}p3" "${disk}p4" )
    else
        choices+=( "${disk}1" "${disk}2" "${disk}3" "${disk}4" )
    fi

    # Choose a partition for the root device
    root_dev=$(whiptail --title "Get Physical Volume Device" --radiolist \
    "What partition for your Physical Volume Group?  (sda2, nvme0n1p2, sdb2, etc)" 20 50 4 \
    "${choices[0]}" "" OFF \
    "${choices[1]}" "" ON \
    "${choices[2]}" "" OFF \
    "${choices[3]}" "" OFF 3>&1 1>&2 2>&3) 
    ROOT_DEVICE=/dev/"$root_dev"

    # get root partition or volume
    rootsize=$(whiptail --title "Get Size of Root Partition or Volume" --radiolist \
        "What size for your root partition? (15G, 50G, 100G, etc)" 20 50 4 \
        "15G" "" ON \
        "50G" "" OFF \
        "75G" "" OFF \
        "100G" "" OFF 3>&1 1>&2 2>&3)
    ROOT_SIZE="$rootsize"

    # get size of swap partition or volume
    swapsize=$(whiptail --title "Get Size of Swap Partition or Volume" --radiolist \
        "What size for your swap partition? (4G, 8G, 16G, etc)" 20 50 5 \
    "4G" "" ON \
    "8G" "" OFF \
    "16G" "" OFF \
    "32G" "" OFF \
    "64G" "" OFF 3>&1 1>&2 2>&3) 
    SWAP_SIZE="$swapsize"

    # Get EFI or BOOT partition?
    if $(efi_boot_mode); then

        efi_dev=$(whiptail --title "Get EFI Device" --radiolist \
            "What partition for your EFI Device?  (sda1 nvme0n1p1, sdb1, etc)" 20 50 4 \
            "${choices[0]}" "" ON \
            "${choices[1]}" "" OFF \
            "${choices[2]}" "" OFF \
            "${choices[3]}" "" OFF  3>&1 1>&2 2>&3) 

        # show an infobox while we wait for partitions
        TERM=ansi whiptail --backtitle "CREATING PARTITIONS" --title "Creating Your Partitions" --infobox "Please wait a moment while we create your partitions..." 8 40

        EFI_DEVICE=/dev/"$efi_dev"
        EFI_SIZE=512M   # This is a duplicate line

        # Create the physical partitions
        sgdisk -Z "$IN_DEVICE"                                    &>> $LOGFILE
        sgdisk -n 1::+"$EFI_SIZE" -t 1:ef00 -c 1:EFI "$IN_DEVICE" &>> $LOGFILE
        sgdisk -n 2 -t 2:8e00 -c 2:VOLGROUP "$IN_DEVICE"          &>> $LOGFILE

    else
        # get boot partition (we're using MBR with LVM here)
        boot_dev=$(whiptail --title "Get Boot Device" --radiolist \
            "What partition for your Boot Device? (sda1 nvme0n1p1, sdb1, etc)" 20 50 4 \
            "${choices[0]}" "" ON \
            "${choices[0]}" "" OFF \
            "${choices[0]}" "" OFF \
            "${choices[0]}" "" OFF  3>&1 1>&2 2>&3) 

        # show an infobox while we wait for partitions
        TERM=ansi whiptail --backtitle "CREATING PARTITIONS" --title "Creating Your Partitions" --infobox "Please wait a moment while we create your partitions..." 8 40

        BOOT_DEVICE=/dev/"$boot_dev"
        BOOT_SIZE=512M

        # The HERE document requires zero indentation:

cat > /tmp/sfdisk.cmd << EOF
$BOOT_DEVICE : start= 2048, size=+$BOOT_SIZE, type=83, bootable
$ROOT_DEVICE : type=83
EOF
        # Using sfdisk because we're talking MBR disktable now...
        sfdisk /dev/sda < /tmp/sfdisk.cmd   &>> $LOGFILE

        # format the boot partition
        format_disk "$BOOT_DEVICE" boot
    fi

    # run cryptsetup on root device  # uncomment this later
    [[ "$USE_CRYPT" == 'TRUE' ]] && crypt_setup "$ROOT_DEVICE"

    # run cryptsetup on root device  # uncomment this later
    if [[ "$USE_CRYPT" == 'TRUE' ]] ; then
        pvcreate /dev/mapper/"$CRYPT_PART"                 &>> $LOGFILE
    else
        # create the physical volumes
        pvcreate "$ROOT_DEVICE"                &>> $LOGFILE
    fi


    # Setup LV's one way for encryption, another way without
    # Note:  Haven't removed old comments because I'm still not sure new way will
    # work.  Keep both methods around until I verify them
    if [[ "$USE_CRYPT" == 'TRUE' ]] ; then
        # create vg on encrypted partition
        vgcreate "$VOL_GROUP" "$CRYPT_PART"   &>> $LOGFILE

        # You can extend with 'vgextend' to other devices too

        # create the volumes with specific size
        lvcreate -L "$ROOT_SIZE" "$CRYPT_PART" -n "$LV_ROOT"   &>> $LOGFILE
        #lvcreate -L "$ROOT_SIZE" "$VOL_GROUP" -n "$LV_ROOT"   &>> $LOGFILE
        lvcreate -L "$SWAP_SIZE" "$CRYPT_PART" -n "$LV_SWAP"   &>> $LOGFILE
        #lvcreate -L "$SWAP_SIZE" "$VOL_GROUP" -n "$LV_SWAP"   &>> $LOGFILE
        lvcreate -l 100%FREE  "$CRYPT_PART" -n "$LV_HOME"      &>> $LOGFILE
        #lvcreate -l 100%FREE  "$VOL_GROUP" -n "$LV_HOME"      &>> $LOGFILE
        
        # Format SWAP 
        format_disk /dev/"$CRYPT_PART"/"$LV_SWAP" swap
        # insert the vol group kernel module
        modprobe dm_mod                                       &>> $LOGFILE
        
        # activate the vol group
        vgchange -ay                                          &>> $LOGFILE

        ## format the volumes
        format_disk /dev/"$CRYPT_PART"/"$LV_ROOT"  root
        ## Format the EFI partition:  have to do this AFTER the 
        ## root partition or else it won't get mounted properly
        if $( efi_boot_mode ) ; then
            format_disk "$EFI_DEVICE" efi
        else
            format_disk "$BOOT_DEVICE" boot
        fi
            #[[ ! $(efi_boot_mode ) ]] && format_disk "$BOOT_DEVICE" boot 
            #[[ $(efi_boot_mode ) ]] && format_disk "$EFI_DEVICE" efi 
        format_disk /dev/"$CRYPT_PART"/"$LV_HOME"  home
    else
        # create the volume group
        vgcreate "$VOL_GROUP" "$ROOT_DEVICE"   &>> $LOGFILE
        # You can extend with 'vgextend' to other devices too

        # create the volumes with specific size
        lvcreate -L "$ROOT_SIZE" "$VOL_GROUP" -n "$LV_ROOT"   &>> $LOGFILE
        lvcreate -L "$SWAP_SIZE" "$VOL_GROUP" -n "$LV_SWAP"   &>> $LOGFILE
        lvcreate -l 100%FREE  "$VOL_GROUP" -n "$LV_HOME"      &>> $LOGFILE
        
        # Format SWAP 
        format_disk "/dev/$VOL_GROUP/$LV_SWAP" swap
    
        # insert the vol group kernel module
        modprobe dm_mod                                       &>> $LOGFILE
        
        # activate the vol group
        vgchange -ay                                          &>> $LOGFILE

        ## format the volumes
        format_disk "/dev/$VOL_GROUP/$LV_ROOT"  root
        ## Format the EFI partition:  have to do this AFTER the 
        ## root partition or else it won't get mounted properly
        if $( efi_boot_mode ); then
            format_disk "$EFI_DEVICE" efi
        else
            format_disk "$BOOT_DEVICE" boot
            #[[ ! $(efi_boot_mode ) ]] && format_disk "$BOOT_DEVICE" boot 
            #[[ $(efi_boot_mode ) ]] && format_disk "$EFI_DEVICE" efi 
        fi
        format_disk "/dev/$VOL_GROUP/$LV_HOME"  home
    fi
    
    # examine our work here
    lsblk > /tmp/filesystems_created
    whiptail --title "LV's Created and Mounted" --backtitle "Filesystem Created" \
        --textbox /tmp/filesystems_created 30 70
    sleep 4
    startmenu
}

# MOUNT PARTION
mount_part(){
    # Mount the device ($1) and the mount point ($2)
    # 2nd parameter is mount point
    device=$1; mt_pt=$2

    # both efi and non-efi systems need /mnt/boot
    [[ ! -d /mnt/boot ]] && mkdir /mnt/boot &>> $LOGFILE

    # only efi systems need /mnt/boot/efi
    $(efi_boot_mode) && ! [ -d /mnt/boot/efi ] && mkdir /mnt/boot/efi &>> $LOGFILE

    # if mt_pt doesn't exist, create it if possible
    [[ ! -d "$mt_pt" ]] && mkdir "$mt_pt"   &>>$LOGFILE
    
    # Do the deed (Mount it!)  Don't forget the logfile
    mount "$device" "$mt_pt" 2>&1  &>>$LOGFILE

    # Check if we've succeeded or not
    if [[ "$?" -eq 0 ]]; then
        echo "====== $device mounted successfully on $mt_pt ======" &>>$LOGFILE
    else

        TERM=ansi whiptail --title "Mount NOT successful" \
            --msgbox "$device failed mounting on $mt_pt" 8 65
        echo "!!!### ===== $device failed mounting on $mt_pt ===== ###!!!"
        show_error "$device failed to mount on $mt_pt"
    fi
    return 0
}

# FORMAT NON-LVM DEVICE
format_disk(){
    # I'm using 'slice' in the BSD disk slice sense here
    # I'm pretty sure it means same as 'partition'
    device=$1; slice=$2

    # only do efi slice if efi_boot_mode return 0; else return 0

    if [[ $slice == 'efi' ]]; then
        $(efi_boot_mode) || show_error "You can't create an EFI partition with an MBR disktable!"
    fi

    case $slice in 
        efi ) mkfs.fat -F32 "$device"           &>> $LOGFILE
            mount_part "$device" /mnt/boot/efi  &>> $LOGFILE
            ;;
        home  ) mkfs.ext4 "$device"             &>> $LOGFILE
            mkdir /mnt/home                     &>> $LOGFILE
            mount_part "$device" /mnt/home      &>> $LOGFILE
            ;;
        boot  ) mkfs.ext4 "$device"             &>> $LOGFILE
            mount_part $device /mnt/boot        &>> $LOGFILE
            ;;
        root  ) mkfs.ext4 "$device"             &>> $LOGFILE
            mount_part "$device" /mnt           &>> $LOGFILE
            ;;
        swap  ) mkswap "$device"                &>> $LOGFILE
                swapon "$device"                &>> $LOGFILE

                TERM=ansi whiptail --title "Swap space now on" \
                    --infobox "Swap space should now be turned on..." 8 50
                sleep 3
            ;;
        * ) whiptail --title "Bad disk format request" \
            --infobox "Can't make that disk * * format" 8 60 && sleep 5  && startmenu ;;
    esac
}

# PARTITION NON-LVM DISK
part_disk(){
    device=$1 ; IN_DEVICE="/dev/$device"

    if $( whiptail --backtitle "DISK FORMATTING" --title "Formatting Drive" --yesno "Partitioning Drive EFI: $EFI_SIZE ROOT: $ROOT_SIZE SWAP: $SWAP_SIZE HOME: $HOME_SIZE  OK to proceed?" 10 59 3>&1 1>&2 2>&3 ) ; then
    
    
        if $(efi_boot_mode); then
                sgdisk -Z "$IN_DEVICE"                                         &>> $LOGFILE
                sgdisk -n 1::+"$EFI_SIZE" -t 1:ef00 -c 1:EFI "$IN_DEVICE"      &>> $LOGFILE
                sgdisk -n 2::+"$ROOT_SIZE" -t 2:8300 -c 2:ROOT "$IN_DEVICE"    &>> $LOGFILE
                sgdisk -n 3::+"$SWAP_SIZE" -t 3:8200 -c 3:SWAP "$IN_DEVICE"    &>> $LOGFILE
                sgdisk -n 4 -c 4:HOME "$IN_DEVICE"                             &>> $LOGFILE
        else
        # For non-EFI. Eg. for MBR systems 
cat > /tmp/sfdisk.cmd << EOF
$BOOT_DEVICE : start= 2048, size=+$BOOT_SIZE, type=83, bootable
$ROOT_DEVICE : size=+$ROOT_SIZE, type=83
$SWAP_DEVICE : size=+$SWAP_SIZE, type=82
$HOME_DEVICE : type=83
EOF
        # Using sfdisk because we're talking MBR disktable now...
        sfdisk /dev/sda < /tmp/sfdisk.cmd   &>> $LOGFILE
        fi
    
    else
        whiptail --title "Not Partitioning Disk" --msgbox "Sending you back to startmenu. OK?"  8 60
        startmenu
    fi

    # SHOW RESULTS:
    status=$(fdisk -l "$IN_DEVICE"; lsblk -f "$IN_DEVICE")
    whiptail --backtitle "CREATED PARTITIONS" --title "Current Disk Status" --msgbox "$status  OK to continue." 30 75

    # ROOT DEVICE
    root_device=$(whiptail --title "ROOT DEVICE" --inputbox "What's your rootdevice? (sda2, nvmen1p2, sdb2, etc)" 30 75 3>&1 1>&2 2>&3)
    ROOT_SLICE="/dev/$root_device"
    [[ -n "$root_device" ]] && format_disk "$ROOT_SLICE" root


    # EFI_DEVICE
    efi_dev_message=$(echo "EFI device name (leave empty if not EFI/GPT) (sda1, nvmen1p1, etc)?")
    efi_device=$(whiptail --title "Get EFI Device Name" --inputbox "$efi_dev_message" 30 75 3>&1 1>&2 2>&3)
    EFI_SLICE="/dev/$efi_device"
    [[ -n "$efi_device" ]] && format_disk "$EFI_SLICE" efi

    # SWAP_DEVICE
    swap_dev_message=$(echo "Swap device name? (sda3, nvmen1p3, etc) (leave empty if no swap device)")
    swap_device=$(whiptail --title "Get Swap Device" --inputbox "$swap_dev_message" 30 75 3>&1 1>&2 2>&3)
    SWAP_SLICE="/dev/$swap_device"
    [[ -n "$swap_device" ]] && format_disk "$SWAP_SLICE" swap

    # HOME_DEVICE
    home_dev_message=$(echo "Home device name? (sda4, nvmen1p4, etc) (leave empty if no home device)")
    home_device=$(whiptail --title "Get Home Device" --inputbox "$home_dev_message" 30 75 3>&1 1>&2 2>&3)
    HOME_SLICE="/dev/$home_device"
    [[ -n "$home_device" ]] && format_disk "$HOME_SLICE" home

    # CHECK IF IT HAPPENED CORRECTLY
    message=$(lsblk "$IN_DEVICE" && echo "Disks should be partitioned and mounted. OK to continue")
    whiptail --backtitle "DISKS PARTITIONED, FORMATTED and MOUNTED" --title "DISKS OKAY?" --msgbox "$message" 25 75 
}

# ENCRYPT DISK WHEN POWER IS OFF
crypt_setup(){
    # Takes a disk partition as an argument
    # Give msg to user about purpose of encrypted physical volume
    message="You are about to encrypt a physical volume.  Your data will be stored in an encrypted state when powered off.  Your files will only be protected while the system is powered off.  This could be very useful if your laptop gets stolen, for example. Hit OK to continue."

    back_message="ENCRYPTING PARTITION WITH LUKS"
    title_message="Encrypting Paritition"

    whiptail --backtitle "$back_message" --title "$title_message" --msgbox "$message" 15 80

    #read -p "Encrypting a disk partition. Please enter a memorable passphrase: " -s passphrase
    passphrase=$( whiptail --backtitle "$back_message" --title "$title_message" --passwordbox \
        "Please enter a memorable passphrase: " 12 80 3>&1 1>&2 2>&3 )

    echo "$passphrase" > /tmp/passphrase

    #echo -n "$passphrase" | cryptsetup -q luksFormat $1 -   2>&1 &>>$LOGFILE
    cryptsetup -y -v luksFormat $1 --key-file /tmp/passphrase   2>&1 &>>$LOGFILE
    #echo -n "$passphrase" | cryptsetup -q luksFormat --hash=sha512 --key-size=512 --cipher=aes-xts-plain64 --verify-passphrase $1 -  2>&1 &>>$LOGFILE

    cryptsetup luksOpen  $1 $CRYPT_PART   2>&1 &>>$LOGFILE      

    cryptsetup -v status $CRYPT_PART    2>&1 &>>$LOGFILE

    term=ANSI whiptail --backtitle "$back_message" --title "$title_message" --infobox "Wiping every byte of device with zeroes, could take a while..." 24 80

    ## Shouldn't be using mapper at this point!!!
    dd if=/dev/zero of=/dev/mapper/"$CRYPT_PART" bs=1M    2>&1  &>>$LOGFILE
    cryptsetup luksClose "$CRYPT_PART"                    2>&1  &>>$LOGFILE
    
    term=ANSI whiptail --backtitle "$back_message" --title "$title_message" --infobox "Filling header of device with random data..." 24 80
    dd if=/dev/urandom of="$1" bs=512 count=20480     2>&1  &>>$LOGFILE
}

# DISPLAY AND CHOOSE DISK PREP METHODS

## This line could be put into the menu below if we want to use disk encryption.
## It doesn't work yet, however.

#        "E"   "Prepare Installation Disk Encryption and LVM"   \
#            "E") USE_LVM='TRUE'; USE_CRYPT='TRUE'; check_tasks 4; lv_create ;;
            

diskmenu(){

    while true ; do

        diskmenupick=$(whiptail --backtitle "PARTION DISKS" --title "DISK PARTITIONS" \
            --menu "Prepare Installation Disk (Choose One)" 18 80 6 \
        "N"   "Prepare Installation Disk with Normal Partitions" \
        "L"   "Prepare Installation Disk with LVM"   \
        "M"   "Manually Partition Disk with parted "   \
        "R"   "Return to previous menu"   3>&1 1>&2 2>&3 ) 

        case $diskmenupick in

            "N") check_tasks 4; get_install_device ;;

            "L") USE_LVM='TRUE'; check_tasks 4; lv_create ;;

            "M") device=$(choose_disk); clear; bash --init-file <(parted /dev/"$device"  1>&1 2>&2) ; check_tasks 4 ;;

            "R") startmenu ;;
        esac
    done
}

###################  INSTALLATION FUNCTIONS #################################

# INSTALL ESSENTIAL PACKAGES
install_base(){
    # install lvm2 hook if we're using LVM
    [[ $USE_LVM == 'TRUE'  ]] && base_system+=( "lvm2" )
    pacstrap /mnt "${base_system[@]}"   &>> $LOGFILE
    [[ -L /dev/mapper/arch_vg-ArchRoot ]] && lvm_hooks &>>$LOGFILE
}


# SOME MORE ESSENTIAL NETWORK STUFF
install_essential(){
    arch-chroot /mnt pacman -S "${base_essentials[@]}"  --noconfirm          &>>$LOGFILE
    arch-chroot /mnt pacman -S "${network_essentials[@]}" --noconfirm        &>>$LOGFILE

    # ENABLE SERVICES
    for service in "${my_services[@]}"; do
        arch-chroot /mnt systemctl enable "$service"  &>>$LOGFILE 2>&1
    done
}

# TURN ON OS-PROBER
turnon_os_prober(){
    echo "GRUB_DISABLE_OS_PROBER=false" >> /mnt/etc/default/grub
}

# INSTALL BOOTLOADER
install_grub(){

    TERM=ansi whiptail --backtitle "INSTALLING GRUB" --title "Installing GRUB" --infobox \
        "Installing GRUB" 9 70

    sleep 2
    arch-chroot /mnt pacman -S grub os-prober --noconfirm  &>>$LOGFILE

    # CHECK FOR OTHER OSES (By default this is not enabled)
    turnon_os_prober

    # Grub gets installed differently on efi- non-efi-systems
    if $(efi_boot_mode); then

        arch-chroot /mnt pacman -S efibootmgr --noconfirm  &>>$LOGFILE

        # /boot/efi should aready be mounted
        [[ ! -d /mnt/boot/efi ]] && echo "no /mnt/boot/efi directory!!!" &>>$LOGFILE  && exit 1 

        arch-chroot /mnt grub-install "$IN_DEVICE" --target=x86_64-efi \
            --bootloader-id=GRUB --efi-directory=/boot/efi  &>>$LOGFILE

        TERM=ansi whiptail --backtitle "GRUB INSTALLED" --title "GRUB Installed" \
            --infobox "GRUB Installed!" 9 70

        sleep 2

    else

        arch-chroot /mnt grub-install "$IN_DEVICE"  &>>$LOGFILE

        [[ $? == 0 ]] && TERM=ansi whiptail --backtitle "BOOT LOADER INSTALLED" --title \
            "MBR Bootloader Installed" --infobox "MBR Bootloader Installed Successfully!" 9 70

        whiptail --title "LOGFILE for Grub Installation" \
            --textbox /tmp/install.log 30 79 --scrolltext

        sleep 2
    fi

    # create the grub.cfg file!
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg &>>$LOGFILE
        
    # How did we do?
    whiptail --backtitle "GRUB.CFG INSTALLED" --title "/boot/grub/grub.cfg installed" \
        --msgbox "Please click OK to proceed." 8 70
    whiptail --backtitle "GRUB.CFG LOGFILE" --title "/boot/grub/grub.cfg installed" \
        --textbox /tmp/install.log --scrolltext 38 80
}

# WIFI (BCM4360) IF NECESSARY  # wifi_drivers should equal your PCI or USB wifi adapter!!!
wl_wifi(){

    TERM=ansi whiptail --title "Installing $wifi_drivers" --infobox \
        "Installing $wifi_drivers..." 10 70 

    arch-chroot /mnt pacman -S "${wifi_drivers[@]}" --noconfirm  &>>$LOGFILE

    [[ "$?" -eq 0 ]] && whiptail --title "Success!" --infobox "$wifi_drivers Installed!" 10 70

    sleep 3
}

# PICK YOUR XSERVER AND DESKTOP
pick_desktop(){

    card=$(lspci | grep VGA | sed 's/^.*: //g')

    driver=$(whiptail --title "Please Choose Your X Server: (spacebar)" --radiolist \
    "You're running a $card" 20 80 7 \
    "xf86-video-amdgpu"         "AMD GPUs"                               OFF \
    "xf86-video-ati"            "ATI cards"                              OFF \
    "xf86-video-intel"          "Intel Video Chipsets"                   OFF \
    "xf86-video-nouveau"        "Nvidia Chipsets (Open Source)"          OFF \
    "xf86-video-openchrome"     "Chromebook video chipsets"              OFF \
    "xf86-video-vmware"         "Use for virtual machines"               ON \
    "xf86-video-fbdev"          "Only for frame buffer devices!!!"       OFF 3>&1 1>&2 2>&3 )  

    # This selection should overwrite the global choice if necessary
    graphics_driver=( "$driver" )

    choice=$(whiptail --title "Please Choose Your Desktop: (spacebar)" --radiolist \
    "Default Desktop is Cinnamon" 20 80 9 \
    "Cinnamon" "Gnome based desktop that is intuitive and familiar"        ON \
    "Mate"     "Originally based on Gnome 2, traditional, lightweight"     OFF \
    "Gnome"    "Modern and even bleeding Edge Desktop"                     OFF \
    "XFCE"     "Lightweight and full featured Desktop"                     OFF \
    "KDE"      "A large but heavy-weight DE based on QT toolkit"           OFF \
    "i3gaps"   "A very popular tiling window manager"                      OFF \
    "Qtile"    "A terrific tiling window manager written in Python"        OFF \
    "Xmonad"   "A favorite of tiling WM fans, written in Haskell"          OFF \
    "Awesome"  "Another favorite tiling WM written in Lua"                 OFF 3>&1 1>&2 2>&3 )

    case $choice in 
        "Cinnamon" ) mydesktop=( "${cinnamon_desktop[@]}" ) ;;
        "Mate"     ) mydesktop=( "${mate_desktop[@]}" ) ;;
        "Gnome"    ) mydesktop=( "${gnome_desktop[@]}" )   ;;
        "XFCE"     ) mydesktop=( "${xfce_desktop[@]}" )  ;;
        "KDE"      ) mydesktop=( "${kde_desktop[@]}" )  ;;
        "i3gaps"   ) mydesktop=( "${i3gaps_desktop[@]}" )  ;;
        "Qtile"    ) mydesktop=( "${qtile_desktop[@]}" ) ;;
        "Xmonad"   ) mydesktop=( "${xmonad_desktop[@]}" ) ;;
        "Awesome"  ) mydesktop=( "${awesome_desktop[@]}" ) ;;
        * )          mydesktop=( "${cinnamon_desktop[@]}" )
    esac
}

# INSTALL XORG AND DESKTOP
install_desktop(){

    # UPDATE FROM LATEST DESKTOP CHOICE
    desktop=( "${mydesktop[@]}" )

    # EXTRA PACKAGES, FONTS, THEMES, CURSORS
    arch-chroot /mnt pacman -S "${basic_x[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${extra_x1[@]}" --noconfirm    &>>$LOGFILE
    arch-chroot /mnt pacman -S "${extra_x2[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${extra_x3[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${extra_x4[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${devel_stuff[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${printing_stuff[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${multimedia_stuff[@]}" --noconfirm   &>>$LOGFILE

    # DRIVER FOR GRAPHICS CARD, DESKTOP, DISPLAY MGR
    arch-chroot /mnt pacman -S "${display_mgr[@]}" --noconfirm  &>>$LOGFILE 
    arch-chroot /mnt pacman -S "${graphics_driver[@]}" --noconfirm    &>>$LOGFILE 

    ## MYDESKTOP gets installed here, either default or user choice
    #arch-chroot /mnt pacman -S "${mydesktop[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${desktop[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt systemctl enable "${display_mgr[@]}" &>>$LOGFILE 2>&1

    ## Give the lightdm service a background
    sed -i 's|^#background=|background=/usr/share/backgrounds/archlinux/wave.png|g' /mnt/etc/lightdm/lightdm-gtk-greeter.conf
}

install_extra_stuff(){
    arch-chroot /mnt pacman -S "${all_extras[@]}" --noconfirm   &>>$LOGFILE

    # restart services so lightdm gets all WM picks
    for service in "${my_services[@]}"; do
        arch-chroot /mnt systemctl enable "$service"   &>>$LOGFILE
    done
}


#################### CONFIGURATION FUNCTIONS  ###################################

# GENERATE FSTAB
gen_fstab(){
    #clear
    TERM=ansi whiptail --title "Generating FSTAB" --infobox "Generating /mnt/etc/fstab" 8 75
    genfstab -U /mnt >> /mnt/etc/fstab
    sleep 3

    # take a look at new fstab file
    whiptail --backtitle "Checkout New /etc/fstab" --title \
        "Here's your new /etc/fstab" --textbox /mnt/etc/fstab --scrolltext 30 85
}

# TIMEZONE
set_tz(){
    
    TERM=ansi whiptail --title "Setting timezone to $TIMEZONE" --infobox \
        "Setting Timezone to $TIMEZONE" 8 75
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
    arch-chroot /mnt hwclock --systohc --utc 
    message=$(arch-chroot /mnt date)
    whiptail --backtitle "SETTING HWCLOCK and TIMEZONE and Hardware Date" --title \
        "HW CLOCK AND TIMEZONE SET to $TIMEZONE" --msgbox "$message" 8 78
}

choose_locale(){
    locales=()

    if $(whiptail --backtitle "KEEP LOCALE?" --title "Want to keep LOCALE as default en_US.UTF-8?" \
        --yesno "Choose whether to keep default en_US.UTF-8" --yes-button "Keep en_US.UTF-8" \
        --no-button "Change LOCALE" 20 80 3>&1 1>&2 2>&3 ); then

        LOCALE=${LOCALE:="en_US.UTF-8"}
    else
        # Here's the array of available locales:
        for locale in $(egrep '^#?[a-z]{2}_*' /etc/locale.gen | awk '{print $1}' | sed 's/^#//g'); do
            locales+=( $(printf "%s\t\t%s\n" $locale "Locale")  )
        done
        # whiptail selection menu of all available locales on system
        LOCALE=$(eval `resize`; whiptail --backtitle "CHOOSE LOCALE" --title "Choose Your Locale" \
            --menu "Default Locale is en_US.UTF-8" $LINES $COLUMNS $(( $LINES - 8 )) "${locales[@]}" 3>&1 1>&2 2>&3 )
    fi

    LOCALE=${LOCALE:="en_US.UTF-8"}

}

# LOCALE
set_locale(){

    LOCALE=${LOCALE:="en_US.UTF-8"}
    sleep 2
    arch-chroot /mnt sed -i "s/#$LOCALE/$LOCALE/g" /etc/locale.gen
    arch-chroot /mnt locale-gen   &>>$LOGFILE

    echo "LANG=$LOCALE" > /mnt/etc/locale.conf 
    export LANG="$LOCALE"

    result=$(cat /mnt/etc/locale.conf)
    whiptail --backtitle "LOCALE SET TO $LOCALE" --title "Locale: $LOCALE" \
        --msgbox "$result" 8 79
}

# HOSTNAME
set_hostname(){
    namevar=$(whiptail --title "Hostname" --inputbox \
        "What is your new hostname?" 20 40 3>&1 1>&2 2>&3)
    echo "$namevar" > /mnt/etc/hostname

cat > /mnt/etc/hosts <<HOSTS
127.0.0.1      localhost
::1            localhost
127.0.1.1      $namevar.localdomain     $namevar
HOSTS

    message=$(echo -e "/etc/hostname and /etc/hosts files configured...\n" && echo)
    message+=$(echo -e "\n/etc/hostname: \n" && cat /mnt/etc/hostname)
    message+=$(echo -e "\n\n/etc/hosts: \n" && cat /mnt/etc/hosts)
    whiptail --backtitle "/etc/hostname & /etc/hosts" --title "Files created" \
        --msgbox "$message" 25 75
}


# ADD A USER ACCT
add_user_acct(){

    TERM=ansi whiptail --backtitle "ADDING SUDO USER" --title \
        "Adding sudo + user acct..." --infobox "Adding sudo user to new system" 10 50 

    sleep 2

    arch-chroot /mnt pacman -S sudo bash-completion sshpass  --noconfirm      &>>$LOGFILE
    arch-chroot /mnt sed -i 's/# %wheel/%wheel/g' /etc/sudoers
    arch-chroot /mnt sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers  

    sudo_user=$(whiptail --backtitle "SUDO USERNAME" --title \
        "Please provide sudo username" --inputbox \
        "Please provide a sudo username: " 8 40 3>&1 1>&2 2>&3 )

    TERM=ansi whiptail --title "Creating sudo user and adding to wheel" --infobox \
        "Creating $sudo_user and adding $sudo_user to sudoers..." 10 70

    arch-chroot /mnt useradd -m -G wheel "$sudo_user"  &>>$LOGFILE
    sleep 2  # Need this so user has time to read infobox above

    user_pass=$(whiptail --passwordbox "Please enter your new user's password: " --title \
        "Getting user password" 8 78 3>&1 1>&2 2>&3 )

    echo -e "$user_pass\n$user_pass" | arch-chroot /mnt passwd "$sudo_user"  &>>$LOGFILE

    TERM=ansi whiptail --title "Sudo User Password Created" --infobox \
        "sudo user password updated" 10 70
    sleep 3
}



##########################################
###    SCRIPT STARTS
##########################################

startmenu(){
    check_reflector
    while true ; do
        menupick=$(
        whiptail --backtitle "Daves ARCHlinux Installer" --title "Main Menu" --menu "Your choice?" 30 70 20 \
            "K"   "[$(echo ${completed_tasks[1]}]    Change keyboard keymap )"  \
            "L"   "[$(echo ${completed_tasks[2]}]    Choose your TimeZone and Locale)"  \
            "C"   "[$(echo ${completed_tasks[3]}]    Check connection and date)"  \
            "D"   "[$(echo ${completed_tasks[4]}]    Prepare Installation Disk)"  \
            "B"   "[$(echo ${completed_tasks[5]}]    Install Base System)"        \
            "F"   "[$(echo ${completed_tasks[6]}]    New FSTAB and TZ/Locale)"    \
            "H"   "[$(echo ${completed_tasks[7]}]    Set new hostname)"           \
            "R"   "[$(echo ${completed_tasks[8]}]    Set root password)"          \
            "M"   "[$(echo ${completed_tasks[9]}]    Install More network essentials)" \
            "U"   "[$(echo ${completed_tasks[10]}]    Add user + sudo account) "   \
            "W"   "[$(echo ${completed_tasks[11]}]    Install Wifi Drivers )"      \
            "G"   "[$(echo ${completed_tasks[12]}]   Install grub)"               \
            "E"   "[$(echo ${completed_tasks[13]}]   Choose Graphics Driver and Desktop Environment)" \
            "X"   "[$(echo ${completed_tasks[14]}]   Install Xorg + Desktop)"     \
            "I"   "[$(echo ${completed_tasks[15]}]   Install Extra Window Mgrs)"  \
            "P"   "[$(echo ${completed_tasks[16]}]   Check for pkg name changes)" \
            "Q"   "[$(echo ${completed_tasks[17]}]   Quit Script) "  3>&1 1>&2 2>&3
        )

        case $menupick in

            "K")  change_kb; check_tasks 1 ;;

            "L")  choose_locale; change_tz; check_tasks 2 ;;

            "C")  check_connect; time_date; check_tasks 3 ;;

            "D")  diskmenu ;;

            "B")  USE_LVM='TRUE'; 
                  specialprogressgauge install_base "Installing base system..." "INSTALLING BASE SYSTEM"; 
                  whiptail --backtitle "BASE SYSTEM INSTALLED" --title "Base system installed!" \
                      --msgbox "Your base system has been installed.  Click OK to continue." 10 80;
                  whiptail --backtitle "YOUR LOGFILE FOR INSTALLATION" --title "LOGFILE for your installation" \
                      --textbox /tmp/install.log --scrolltext 30 80;
                  check_tasks 5 ;;

            "F")  gen_fstab; set_locale; set_tz; check_tasks 6 ;;

            "H")  set_hostname; check_tasks 7 ;;

            "R")  password=$(whiptail --passwordbox "Please set your new root password..." \
                      --backtitle "SETTING ROOT PASSWORD" --title "Set new root password"   8 48 3>&1 1>&2 2>&3);
                  echo -e "$password\n$password" | arch-chroot /mnt passwd;
                  check_tasks 8 ;; 

            "M")  specialprogressgauge install_essential "Installing dhcpcd, sshd, ssh, networkmanager, etc..." \
                  "INSTALLING NETWORK ESSENTIALS "; 
                  whiptail --title "Network Essentials Installed" --msgbox "Network Essentials Installed.  OK to continue." 8 78;
                  whiptail --title "Current Install Progress" --textbox /tmp/install.log --scrolltext 25 80;
                  check_tasks 9 ;;

            "U")  add_user_acct; check_tasks 10 ;;

            "W")  wl_wifi; check_tasks 11 ;;

            "G")  install_grub; check_tasks 12 ;;
            
            "E")  pick_desktop; find_card; check_tasks 13 ;;

            "X")  specialprogressgauge install_desktop "Installing Xorg and Desktop Resources..." "INSTALLING XORG"; 
                  whiptail --backtitle "X AND DESKTOPS INSTALLED" --title "Desktops Installed" \
                      --msgbox "Xorg and Extras and Desktops are installed.  OK to check install.log." 8 70 ;
                  whiptail --backtitle "CHECK INSTALL LOGFILE" --title "Xorg Install Log" \
                      --textbox /tmp/install.log --scrolltext 25 80 ;
                  check_tasks 14 ;;

            "I")  specialprogressgauge install_extra_stuff "Installing All My Xorg Extras" "ALL MY EXTRAS FOR XORG"; 
                  whiptail --backtitle "XTRA X STUFF INSTALLED" --title "Extra Desktops Installed" \
                      --msgbox "Extra Goodies Installed.  Click OK to see Install Log." 8 70 ;
                  whiptail --backtitle "CHECK INSTALL LOGFILE" --title "Extra Xorg Stuff Install Log" \
                      --textbox /tmp/install.log --scrolltext 25 80 ;
                  check_tasks 15 ;;

            "P")  validate_pkgs; check_tasks 16 ;;

            "Q")  TERM=ansi whiptail --title "exit installer" \
                  --infobox "Type 'shutdown -h now' and then remove USB/DVD, then reboot" 10 60; 
                  sleep 2; exit 0 ;;
        esac
    done
}

welcome
auto_tz
checkpath
startmenu

