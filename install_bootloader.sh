#!/bin/bash

base_dir=$( dirname "${BASH_SOURCE[0]}" )
work_dir=
work_disk=
root_part=
boot_part=
#boot_loader=
hostname=
kernelname=
menuentry="Funtoo Linux"

source "$( dirname "${BASH_SOURCE[0]}" )/functions.sh"

printf "\nThis script helps to install bootloader"

execution_premission "Sure you want to run this? " || die

boot_part=$(cat /etc/fstab | grep -I /boot | awk '{ print $1 }')
if [ -z "${boot_part##*=*}" ]; then 
	boot_part=$(blkid -o device -t ${boot_part})	
fi

root_part=$(cat /etc/fstab | grep -I "/	" | awk '{ print $1 }')

work_disk="${boot_part%[[:digit:]]*}"

disklabeltype="$(blkid -o value -s PTTYPE ${work_disk})"

#echo "${boot_part} ${root_part} ${work_disk} ${disklabeltype}"
printf "\nMounting boot partition. \n"
try mount ${boot_part} ${work_dir}/boot && { cleanup wait_umount ${work_dir}/boot; cleanup umount -d ${work_dir}/boot; } || { die "Cannot mount ${boot_part}"; }

kernel_list=$(find ${work_dir}/boot -maxdepth 0 -type f -name "kernel*" -name "vmlinuz*" -name "bzImage*")
if [ -n "${kernel_list}" ]; then
	options="${kernel_list}"
	if prompt_select "Select default kernel to load"; then
		kernelname="${selected}"
		read -p "Enter additional params " kernelparams
		read -p "Enter menuentry " menuentry
	fi
else
	echo "No kernels found in boot pertition."
fi

syslinux_files="chain.c32 gfxboot.c32 vesamenu.c32 libutil.c32 libcom32.c32"
options="syslinux grub u-boot uefi"
if prompt_select "Select bootloader"; then
	case ${selected} in
		"syslinux") 
			try install -d ${work_dir}/boot/extlinux
			try extlinux --install ${work_dir}/boot/extlinux
			case ${disklabeltype} in
				"dos") 
					pv -s 440 -S -B 8 ${work_dir}/usr/share/syslinux/mbr.bin > ${work_disk}
					;;
				"gpt")
					try sgdisk ${work_disk} --attributes=1:set:2
					pv -s 440 -S -B 8 ${work_dir}/usr/share/syslinux/gptmbr.bin > ${work_disk}
					;;
				"*") 
					echo -e "Boot loader code not installed! Unsupported disklabel type: ${disklabeltype}";;
			esac
			cp ${work_dir}/usr/share/syslinux/${syslinux_files} ${work_dir}/boot/extlinux/
			touch ${work_dir}/boot/extlinux/extlinux.conf
			;;
		"grub") 
			case ${disklabeltype} in
				"dos") 
					try grub-install --target="i386-pc" --no-floppy ${work_disk}
					;;
				"gpt")
					try grub-install --target="x86_64-efi" --efi-directory=/boot --bootloader-id="{$menuentry}" --recheck ${work_disk}
					;;
				"*") 
					echo -e "Boot loader code not installed! Unsupported disklabel type: ${disklabeltype}"
					;;
			esac
			;;
		"uboot") 
			try mkimage -A arm -T script -C none -n "Boot.scr for android" -d boot.txt boot.scr
			;;
		"uefi") 
			try mkdir -vp /boot/EFI/Boot && cp /boot/${kernelname} /boot/EFI/Boot/bootx64.efi
			;;
		*) ;;
	esac
fi

proceed_cleanup
exit 0
