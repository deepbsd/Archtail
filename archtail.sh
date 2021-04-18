#!/usr/bin/env bash

################################
###    GLOBAL VARIABLES  #######
################################


DISKTABLE=''
IN_DEVICE=''
EFI_SLICE=''
ROOT_SLICE=''
HOME_SLICE=''
SWAP_SLICE=''

# GRAPHICS DRIVERS ETC   ---  change as needed ---
wifi_drivers=(broadcom-wl-dkms iwd)
graphics_driver=(xf86-video-vmware)
display_mgr=(lightdm)

# VOL GROUP VARIABLES
USE_LVM=''   # gets set programmatically
USE_CRYPT='' # gets set programmatically
VOL_GROUP="arch_vg"
LV_ROOT="ArchRoot"
LV_HOME="ArchHome"

# PARTITION SIZES  (You can edit these if desired)
BOOT_SIZE=512M
EFI_SIZE=512M
ROOT_SIZE=13G
SWAP_SIZE=4G     # SWAP_SIZE="$(free | awk '/^Mem/ {mem=$2/1000000; print int(2.2*mem)}')G"
HOME_SIZE=''     # This is set automatically if using LVM

# You can edit this if you want
#TIMEZONE='America/New_York'
TIMEZONE=$(wget -O - -q http://geoip.ubuntu.com/lookup | sed -n -e 's/.*<TimeZone>\(.*\)<\/TimeZone>.*/\1/p')
LOCALE="en_US.UTF-8"

###########  SOFTWARE SETS ###################

# replace with linux-lts or -zen if preferrable
base_system=( base base-devel linux linux-headers dkms linux-firmware vim sudo bash-completion )

base_essentials=(git mlocate pacman-contrib man-db man-pages)

network_essentials=( iwd dhcpcd openssh networkmanager )

my_services=( dhcpcd sshd NetworkManager systemd-homed )

basic_x=( xorg-server xorg-xinit mesa xorg-twm xterm gnome-terminal xorg-xclock xfce4-terminal firefox neofetch screenfetch lightdm-gtk-greeter )

extra_x1=( gkrellm powerline powerline-fonts powerline-vim adobe-source-code-pro-fonts cantarell-fonts gnu-free-fonts ) 

extra_x2=( noto-fonts breeze-gtk breeze-icons gtk-engine-murrine oxygen-icons xcursor-themes adapta-gtk-theme )

extra_x3=( arc-gtk-theme elementary-icon-theme faenza-icon-theme gnome-icon-theme-extras arc-icon-theme lightdm-webkit-theme-litarvan mate-icon-theme ) 

extra_x4=( materia-gtk-theme papirus-icon-theme xcursor-bluecurve xcursor-premium archlinux-wallpaper deepin-community-wallpapers deepin-wallpapers elementary-wallpapers )

cinnamon_desktop=( cinnamon nemo-fileroller )

#####  Include in 'all_extras' array if desired
xfce_desktop=( xfce4 xfce4-goodies )

mate_desktop=( mate mate-extra )

i3gaps_desktop=( i3-gaps dmenu feh rofi i3status i3blocks nitrogen i3status ttf-font-awesome ttf-ionicons )

qtile_desktop=( qtile )

kde_desktop=( lightdm-kde-greeter plasma plasma-wayland-session kde-applications )

## Python3 should be installed by default
devel_stuff=( git nodejs npm npm-check-updates ruby )

printing_stuff=( system-config-printer foomatic-db foomatic-db-engine gutenprint cups cups-pdf cups-filters cups-pk-helper ghostscript gsfonts )

multimedia_stuff=( brasero sox cheese eog shotwell imagemagick sox cmus mpg123 alsa-utils cheese )

all_extras=( "${xfce_desktop[@]}" "${i3gaps_desktop[@]}" "${mate_desktop[@]}" "${devel_stuff[@]}" "${printing_stuff[@]}" "${multimedia_stuff[@]}" )

##  fonts_themes=()    #  in case I want to break these out from extra_x

# This will exclude services because they are often named differently and are duplicates
all_pkgs=( base_system base_essentials network_essentials basic_x extra_x1 extra_x2 extra_x3 extra_x4 cinnamon_desktop xfce_desktop mate_desktop i3gaps_desktop devel_stuff printing_stuff multimedia_stuff qtile_desktop kde_desktop )

completed_tasks=()


##################################
###    FUNCTIONS    ##############
##################################
 
welcome(){
    message="Dave's ARCH Installer will lead you through a menu-driven process to create a base installation of Archlinux on your computer or virtual machine by selecting a group of tasks from a main menu.  "
    whiptail --backtitle "Dave's ARCH Installer (DARCHI)" --title "Welcome to DARCHI!" --msgbox "$message" 15 80 
}

# VERIFY BOOT MODE
efi_boot_mode(){
    ( $(ls /sys/firmware/efi/efivars &>/dev/null) && return 0 ) || return 1
}

# FIND GRAPHICS CARD
find_card(){
    card=$(lspci | grep VGA | sed 's/^.*: //g')
    whiptail --title "Your Video Card" --msgbox  "You're using a $card  Write this down and hit OK to continue." 8 65 3>&2 2>&1 1>&3
}

# IF NOT CONNTECTED
not_connected(){
    clear
    message="No network connection!!!  Perhaps your wifi card is not supported?\nIs your network card plugged in?"
    TERM=ansi whiptail --backtitle "NO NETWORK CONNECTION" --title "Are you connected?" --infobox "$message" 15 70
    sleep 5
    exit 1
}

# ARE WE CONNTECTED??
check_connect(){
    TERM=ansi whiptail --backtitle "Checking Network Connection" --title "Are you connected?" --infobox "Checking connection now..." 15 60 
    if $(ping -c 3 archlinux.org &>/dev/null); then
        TERM=ansi whiptail --backtitle "Network is UP" --title "Network is up!" --infobox "Your network connection is up!" 15 60
        sleep 3
    else
        not_connected
    fi
}

# UPDATE SYSTEM CLOCK
time_date(){
    timedatectl set-ntp true
    time_date_status=$(timedatectl status)
    whiptail --backtitle "Timedate Status" --title "Time and Date Status" --msgbox "$time_date_status" 10 70
}

# CHECK IF TASK IS COMPLETED
check_tasks(){
    # If task already exists in array return falsey
    # Function takes a task number as an argument
    [[ "${completed_tasks[@]}" =~ $1 ]] && return 1
    completed_tasks+=( "$1" )
    return 0
}

# FIND CLOSEST MIRROR
check_reflector(){
    
    whiptail --title "Finding closes mirror" --infobox "Evaluating and finding closest mirrors for Arch repos..." 10 65
    #whiptail --title "Finding closes mirror" --gauge "Evaluating and finding closest mirrors for Arch repos..." 10 65 0
    while true; do
        pgrep -x reflector &>/dev/null || break
        sleep 2
    done
}

# SELECT INSTALLATION DISK
choose_disk(){
       depth=$(lsblk | grep 'disk' | wc -l)
       local DISKS=()
       for d in $(lsblk | grep disk | awk '{printf "%s\n%s \\\n",$1,$4}'); do
            DISKS+=("$d")
       done

       whiptail --title "CHOOSE AN INSTALLATION DISK"  --radiolist " Your Installation Disk: " 20 70 "$depth" \
           "${DISKS[@]}" 3>&2 2>&1 1>&3
            
}

# FORMAT DEVICE
format_disk(){
    device=$1; slice=$2
    # only do efi slice if efi_boot_mode return 0; else return 0
    [[ "$slice" =~ 'efi' && ! "$DISKTABLE" =~ 'GPT' ]] && return 0
    clear
    #echo "Formatting $device with $slice. . ."
    sleep 3
    case $slice in 
        efi ) mkfs.fat -F32 "$device"
            mount_part "$device" /mnt/boot/efi
            ;;
        home  ) mkfs.ext4 "$device"
            mount_part "$device" /mnt/home
            ;;
        root  ) mkfs.ext4 "$device"
            mount_part "$device" /mnt
            ;;
        swap  ) mkswap "$device"
                swapon "$device"
                #echo && echo "Swap space should be turned on now..."
                TERM=ansi whiptail --title "Swap space now on" --infobox "Swap space should now be turned on..." 8 50
                sleep 3
            ;;
        * ) whiptail --title "Bad disk format request" --infobox "Can't make that disk * * format" 8 60 && sleep 5  && startmenu ;;
    esac
}

# PARTITION NON-LVM DISK
part_disk(){
    device=$1 ; IN_DEVICE="/dev/$device"

    if $( whiptail --backtitle "DISK FORMATTING" --title "Formatting Drive" --yesno "Partitioning Drive EFI: $EFI_SIZE ROOT: $ROOT_SIZE SWAP: $SWAP_SIZE HOME: $HOME_SIZE  OK to proceed?" 10 89 ) ; then
        continue
    else
        startmenu
    fi
    
    echo "exiting..."
    exit 0

    if $(efi_boot_mode); then
            sgdisk -Z "$IN_DEVICE"
            sgdisk -n 1::+"$EFI_SIZE" -t 1:ef00 -c 1:EFI "$IN_DEVICE"
            sgdisk -n 2::+"$ROOT_SIZE" -t 2:8300 -c 2:ROOT "$IN_DEVICE"
            sgdisk -n 3::+"$SWAP_SIZE" -t 3:8200 -c 3:SWAP "$IN_DEVICE"
            sgdisk -n 4 -c 4:HOME "$IN_DEVICE"
    else
        # For non-EFI. Eg. for MBR systems 
cat > /tmp/sfdisk.cmd << EOF
$BOOT_DEVICE : start= 2048, size=+$BOOT_SIZE, type=83, bootable
$ROOT_DEVICE : size=+$ROOT_SIZE, type=83
$SWAP_DEVICE : size=+$SWAP_SIZE, type=82
$HOME_DEVICE : type=83
EOF
        # Using sfdisk because we're talking MBR disktable now...
        sfdisk /dev/sda < /tmp/sfdisk.cmd 
    fi

    # SHOW RESULTS:
    status=$(fdisk -l "$IN_DEVICE"; lsblk -f "$IN_DEVICE")
    whiptail --backtitle "CREATED PARTITIONS" --title "Current Disk Status" --msgbox "$status  OK to continue." 30 75

    #echo "Root device name?"; read root_device
    root_device=$(whiptail --title "ROOT DEVICE" --inputbox "What's your rootdevice?" 30 75 3>&1 1>&2 2>&3)
    ROOT_SLICE="/dev/$root_device"
    [[ -n "$root_device" ]] && format_disk "$ROOT_SLICE" root




    lsblk -f "$IN_DEVICE" && echo "EFI device name (leave empty if not EFI/GPT)?"; read efi_device
    EFI_SLICE="/dev/$efi_device"
    echo "Formatting $EFI_SLICE" && sleep 2
    [[ -n "$efi_device" ]] && format_disk "$EFI_SLICE" efi

    lsblk -f "$IN_DEVICE" && echo "Swap device name? (leave empty if no swap device)"; read swap_device
    SWAP_SLICE="/dev/$swap_device"
    echo "Formatting $SWAP_SLICE" && sleep 2
    [[ -n "$swap_device" ]] && format_disk "$SWAP_SLICE" swap

    lsblk -f "$IN_DEVICE" && echo "Home device name? (leave empty if no home device)"; read home_device
    HOME_SLICE="/dev/$home_device"
    echo "Formatting $HOME_SLICE" && sleep 2
    [[ -n "$home_device" ]] && format_disk "$HOME_SLICE" home

    lsblk -f "$IN_DEVICE"
    echo && echo "Disks should be partioned and mounted.  Continue?"; lsblk ; read more
    [[ ! "$more" =~ [yY] ]] && exit 1
}

# INSTALL TO WHAT DEVICE?
get_install_device(){
    device=$(choose_disk)
    if $(efi_boot_mode); then 
        echo && echo "Formatting with EFI/GPT"
        DISKTABLE='GPT'
    else
        echo && echo "Formatting with BIOS/MBR"
        DISKTABLE='MBR'
    fi
    part_disk "$device"
}

get_hostname(){
    whiptail --title "Hostname" --inputbox "What is your new hostname?" 20 40 3>&2 2>&1 1>&3
}

# VALIDATE PKG NAMES IN SCRIPT
validate_pkgs(){
    missing_pkgs=()
    {
    for pkg_arr in "${all_pkgs[@]}"; do
        declare -n arr_name=$pkg_arr
        for pkg_name in "${arr_name[@]}"; do
            if $( pacman -Sp $pkg_name &>/dev/null ); then
                echo -n "" 
            else 
                #echo -n "$pkg_name from $pkg_arr not in repos."
                missing_pkgs+=("$pkg_arr::$pkg_name")
            fi
        done
    done
    } | whiptail --backtitle "Checking repos for packages" --gauge "Verifying Packages..."  6 78 0
    
    whiptail --backtitle "Packages not in repos" --title "These packages not in repos"  --msgbox "${missing_pkgs[@]}" 10 78
}

show_hosts(){
    whiptail --backtitle "/ETC/HOSTS" --title "Your /etc/hosts file" --textbox /etc/hosts 25 80 
}

diskmenu(){

    #check_tasks 2
    while true ; do
        diskmenupick=$(whiptail --backtitle "PARTION DISKS" --title "DISK PARTITIONS" --menu "Prepare Installation Disk (Choose One)" 18 80 4 \
        "N"   "Prepare Installation Disk with Normal Partitions" \
        "L"   "Prepare Installation Disk with LVM"   \
        "E"   "Prepare Installation Disk Encryption and LVM"   \
        "R"   "Return to previous menu"   3>&2 2>&1 1>&3
        ) 

    case $diskmenupick in
        "N") get_install_device ;;
        "L") lv_create ;;
        "E") USE_CRYPT='TRUE'; lv_create ;;
        "R") startmenu ;;
    esac
    done
}


##########################################
###    SCRIPT STARTS
##########################################

#VIDEO_CARD=$(find_card)
#HOSTNAME=$(get_hostname)
##validate_pkgs   # have to execute as root
#
#check_connect

startmenu(){
    check_reflector
    welcome
    while true ; do
        menupick=$(
        whiptail --backtitle "Daves ARCHlinux Installer" --title "Main Menu" --menu "Your choice?" 25 70 16 \
            "C"    "Check connection and date"  \
            "D"    "Prepare Installation Disk"  \
            "B"    "Install Base System"        \
            "F"    "New FSTAB and TZ/Locale"    \
            "H"    "Set new hostname"           \
            "R"    "Set root password"          \
            "M"    "Install more essentials"    \
            "U"    "Add user + sudo account "   \
            "W"    "Install Wifi Drivers "      \
            "G"   "Install grub"               \
            "X"   "Install Xorg + Desktop"     \
            "I"   "Install Extra Window Mgrs"  \
            "V"   "Repopulate Variables "      \
            "P"   "Check for pkg name changes" \
            "L"   "Exit Script "  3>&2 2>&1 1>&3
        )

        case $menupick in
            "C")  check_connect; time_date ;;
            "D")  diskmenu;;
            "B")  install_base; check_tasks 3 ;;
            "F")  gen_fstab; set_tz; set_locale; check_tasks 4 ;;
            "H")  set_hostname; check_tasks 5 ;;
            "R")  echo "Setting ROOT password..."; 
                  arch-chroot /mnt passwd ;; 
            "M")  install_essential; check_tasks 7 ;;
            "U")  add_user_acct; check_tasks 8 ;;
            "W")  wl_wifi; check_tasks 9 ;;
            "G")  install_grub; check_tasks 10 ;;
            "X")  install_desktop; check_tasks 11 ;;
            "I")  install_extra_stuff; check_tasks 12 ;;
            "V")  set_variables ;;
            "P")  validate_pkgs ;;
            "L") TERM=ansi whiptail --title "exit installer" --infobox "Type 'shutdown -h now' and then remove USB/DVD, then reboot" 10 60; sleep 3; exit 0 ;;
        esac
    done
}

startmenu


