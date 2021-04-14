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
    echo "You're using a $card" && echo
}

# IF NOT CONNTECTED
not_connected(){
    clear
    echo "No network connection!!!  Perhaps your wifi card is not supported?"
    echo "Is your network cable plugged in?"
    exit 1
}

show_disks(){
   DISKS=()
   for d in $(lsblk | grep disk | awk '{printf "%s\n%s\n",$1,$4}'); do
        DISKS+=($d)
   done

   max=${#DISKS[@]}
   for ((n=0;n<$max;n+=2)); do
        printf "%s\t%s\t%s\n" ${DISKS[$n]} ${DISKS[(($n+1))]} "OFF"
   done
   echo
}

choose_disk(){
    message=$(show_disks)
    #echo "$message" 
    choice=$(whiptail --title "choose an installation disk" --radiolist "installation disk:" 20 70 4 \
        #'sda' '300G' OFF \
        #'sdb' '200G' OFF \
        #'sdc' '400G' OFF \
        "$message"
        3>&2 2>&1 1>&3 )

    echo -e "\nYou chose $choice\n"
}

choose_disk

