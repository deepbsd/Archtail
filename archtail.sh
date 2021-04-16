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
SWAP_SIZE=2G   # SWAP_SIZE="$(free | awk '/^Mem/ {mem=$2/1000000; print int(2.2*mem)}')G"
HOME_SIZE=12G   # This is set automatically if using LVM

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
    else
        not_connected
    fi
}


choose_disk(){
       depth=$(lsblk | grep 'disk' | wc -l)
       local DISKS=()
       for d in $(lsblk | grep disk | awk '{printf "%s\n%s \\\n",$1,$4}'); do
            DISKS+=("$d")
       done

       whiptail --title "CHOOSE AN INSTALLATION DISK"  --radiolist " Your Installation Disk: " 20 70 "$depth" \
           "${DISKS[@]}" 3>&2 2>&1 1>&3
            
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
    
    echo "${missing_pkgs[@]}"
}

show_hosts(){
    whiptail --backtitle "/ETC/HOSTS" --title "Your /etc/hosts file" --textbox /etc/hosts 25 80 
}

##########################################
###    SCRIPT STARTS
##########################################

#VIDEO_CARD=$(find_card)
#IN_DEVICE=$(choose_disk)
#HOSTNAME=$(get_hostname)
##validate_pkgs   # have to execute as root
#
#check_connect

startmenu(){
    #check_reflector
    while true ; do
        menupick=$(
        whiptail --backtitle "Dave's Arch Linux Installer" --title "Main Menu" --menu "Choose an option" 25 78 16 \ 
            "1" "Check connection and date" \
            "2" "Prepare Installation Disk" \
            "3" "Install Base System" \
            "4" "New FSTAB and TZ/Locale" \
            "5" "Set new hostname" \
            "6" "Set root password" \
            "7" "Install more essentials" \
            "8" "Add user + sudo account " \
            "9" "Install Wifi Drivers "\
            "10" "Install grub" \
            "11" "Install Xorg + Desktop" \
            "12" "Install Extra Window Mgrs " \
            "13" "Repopulate Variables " \
            "14" "Check for pkg name changes" \
            "15" "Exit Script "  3>&2 2>&1 1>&3 
        )

        case $menupick in
            "1") check_connect; time_date; check_tasks 1 ;;
            "2") diskmenu;;
            "3") install_base; check_tasks 3 ;;
            "4") gen_fstab; set_tz; set_locale; check_tasks 4 ;;
            "5") set_hostname; check_tasks 5 ;;
            "6") echo "Setting ROOT password..."; 
                arch-chroot /mnt passwd ; 
                check_tasks 6 ;
                echo "Any key to continue..."; read continue ;;
            "7") install_essential; check_tasks 7 ;;
            "8") add_user_acct; check_tasks 8 ;;
            "9") wl_wifi; check_tasks 9 ;;
            "10") install_grub; check_tasks 10 ;;
            "11") install_desktop; check_tasks 11 ;;
            "12") install_extra_stuff; check_tasks 12 ;;
            "13") set_variables ;;
            "14") validate_pkgs ;;
            "15") echo "exit"  #TERM=ansi whiptail --title "exit installer" --infobox "Type 'shutdown -h now' and then remove USB/DVD, then reboot" 5 60;
                sleep 5;
                exit 0 ;;
        esac
    done
}

startmenu


