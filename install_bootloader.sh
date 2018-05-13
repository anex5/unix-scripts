#!/bin/bash

base_dir=$( dirname "${BASH_SOURCE[0]}" )
work_dir=
work_disk=
root_part=
boot_part=
defkernel=
menu_timeout=60
prompt_timeout=60
#
declare -A menu
declare -A kernelparams

source "$( dirname "${BASH_SOURCE[0]}" )/functions.sh"

gen_syslinux_cfg()
{
	local to=
	local pt=
	local ui=
	for param in ${1}
	do
		IFS=':'
		read -r to pt ui <<< "${param}"
		IFS=$XIFS
		#echo part=${to} mountpoint=${pt} opt=${ui}
		echo -e "UI ${ui}" >> "${2}"
		echo -e "PROMPT ${pt}" >> "${2}"
		echo -e "TIMEOUT ${to}" >> "${2}" 
		echo -e "MENU TITLE WELLCOME" >> "${2}" 
		echo -e "TABMSG" >> "${2}"
		echo -e "MENU BACKGROUND #c00090f0" >> "${2}"
		echo -e "MENU WIDTH 160" >> "${2}"
		echo -e "MENU ROWS 5" >> "${2}"
		echo -e "MENU MARGIN 6" >> "${2}"
		echo -e "MENU VSHIFT 8" >> "${2}"
		echo -e "MENU RESOLUTION $(cat /sys/devices/platform/efi-framebuffer.0/width) $(cat /sys/devices/platform/efi-framebuffer.0/width) " >> "${2}"
		echo -e "MENU COLOR border 30,44 #00000000 #00000000 none" >> "${2}"
		echo -e "MENU COLOR title 0 #9033ccff #00000000 std" >> "${2}"
		echo -e "MENU COLOR disabled 0 #9033ccff #00000000 std" >> "${2}"
		echo -e "MENU COLOR sel 30,47 #ffffffff #e0000000 none" >> "${2}"
		echo -e "MENU COLOR unsel 30,47 #efffffff #00000000 none" >> "${2}"
		echo -e "DEFAULT" >> "${2}"
	done
}

gen_syslinux_cfg_entry()
{
	local label=
	local entry=
	local append=
	for param in ${1}
	do
		IFS=':'
		read -r label entry append <<< "${param}"
		IFS=$XIFS
		#echo part=${label} mountpoint=${entry} opt=${append}
		
		echo -e "LABEL ${label}"
		echo -e "MENU LABEL ${label}" >> "${2}"
		echo -e "LINUX ${entry}" >> "${2}"
		echo -e "APPEND ${append}" >> "${2}"
	done
}

printf "\nThis script helps to install bootloader"

execution_premission "Sure you want to run this? " || die

if ! [ -a "${root_part}" ]; then
	options="$(get_partitions_list)"
	if prompt_select "Select root partition."; then
		root_part="${selected}"
	else
		die
	fi
fi

if ! [ -d "${work_dir}" ]; then
	options="/ $(find /mnt/* -maxdepth 0 -type d)"
	options="${options//${tempfs%\/*}/} new..."
	if prompt_select "Select directory you want to use as the installation mount point."; then
		case ${selected} in
			"new...") work_dir=$(prompt_new_dir /mnt);;
			*) work_dir=${selected};;
		esac
	fi
	work_dir=${work_dir%/}
fi

if ! [ -f ${work_dir}/etc/fstab ]; 
	then die "Cannot find fstab"; 
fi  

boot_part=$(cat ${work_dir}/etc/fstab | grep -I /boot | awk '{ print $1 }')

if [ -z "${boot_part##*=*}" ]; then 
	boot_part=$(blkid -o device -t ${boot_part})	
fi

root_part=$(cat /etc/fstab | grep -I "/	" | awk '{ print $1 }')

work_disk="${boot_part%[[:digit:]]*}"

disklabeltype="$(blkid -o value -s PTTYPE ${work_disk})"

echo "Boot partition found: ${boot_part} disk: ${work_disk} type: ${disklabeltype} \n"

printf "Mounting boot partition. \n"
try mount ${boot_part} ${work_dir}/boot && { cleanup wait_umount ${work_dir}/boot; cleanup umount -d ${work_dir}/boot; } || { die "Cannot mount ${boot_part}"; }

resc_kernel_list=$(find ${work_dir}/boot -maxdepth 1 -type f -name rescue* -printf '%P ')
efi_kernel_list=$(find ${work_dir}/boot -maxdepth 1 -type f -name *.efi -printf '%P ')
kernel_list="$(find ${work_dir}/boot -maxdepth 1 -type f -name kernel* -printf '%P ' \
-or -name vmlinuz* -printf '%P ' -or -name bzImage* -printf '%P ') ${resc_kernel_list} ${efi_kernel_list}"
initramfs_list=$(find ${work_dir}/boot -maxdepth 1 -type f -name "init*" -printf '%P ')

if [ -n "${kernel_list}" ]; then
	options="${kernel_list}"
	if prompt_select "Select default kernel to load"; then
		defkernel="${selected}"	
	fi
	for kernel in ${kernel_list}
	do
		read -p "Enter additional params (ro quiet splash ...) for ${kernel} " kernelparams[kernel]
		read -p "Enter menuentry ${kernel} " menu[kernel]
    done
else
	echo "No kernels found in boot partition."
fi

if [ -n "${initramfs_list}" ]; then
	options="${initramfs_list} skip"
	if prompt_select "Select initramfs"; then
		initramfs="${selected}"	
	fi
fi

options="syslinux grub u-boot uefi"
if prompt_select "Select bootloader"; then
	case ${selected} in
		"syslinux") 
			case ${disklabeltype} in
				"dos") 
					conf_dir=${work_dir}/boot/extlinux
					conf_name=extlinux.conf
					syslinux_files="\{chain.c32,gfxboot.c32,vesamenu.c32,libutil.c32,libcom32.c32\}"
					try mkdir -vp ${conf_dir}
					try extlinux --install ${conf_dir}
					cp ${work_dir}/usr/share/syslinux/${syslinux_files} ${conf_dir}
					pv -s 440 -S -B 8 ${work_dir}/usr/share/syslinux/mbr.bin > ${work_disk}
					gen_syslinux_cfg "${menu_timeout}:${promt_timeout}:vesamenu.c32" ${conf_dir}/${conf_name}
					;;
				"gpt")	
					conf_dir=${work_dir}/boot/efi
					conf_name=syslinux.cfg
					try syslinux --install ${boot_part}
					try mkdir -vp ${work_dir}
					cp ${work_dir}/usr/share/syslinux/efi64/* ${conf_dir}
					mv ${work_dir}/usr/share/syslinux/efi64/syslinux.efi ${conf_dir}/bootx64	
					gen_syslinux_cfg "${menu_timeout}:${promt_timeout}:vesamenu.c32" ${conf_dir}/${conf_name}
					;;
				"*") 
					echo -e "Boot loader code not installed! Unsupported disklabel type: ${disklabeltype}";;
			esac
			if [ -n "${resc_kernel_list}" ]; then
				for kernel in ${resc_kernel_list}
				do
					gen_syslinux_cfg_entry "Syslinux kernel:${kernel}:inird=initram.igz real_root=${root_part}" ${conf_dir}/${conf_name}
    			done
			fi
			if [ -n "${kernel_list}" ]; then
				for kernel in ${kernel_list}
				do
					gen_syslinux_cfg_entry "${menu[kernel]}:${kernel}:${kernelparams[kernel]}" ${conf_dir}/${conf_name}
    				if [ -n "${initramfs}" ]; then
    					echo INITRD initrd=${initramfs} >> ${conf_dir}/${conf_name}
    					echo APPEND real_root=${root_part} >> ${conf_dir}/${conf_name}
    				else
    					echo APPEND root=${root_part} >> ${conf_dir}/${conf_name}
    				fi
    			done
			fi
			;;
		"grub") 
			case ${disklabeltype} in
				"dos") 
					try grub-install --target="i386-pc" --no-floppy ${work_disk}
					;;
				"gpt")
					try grub-install --target="x86_64-efi" --efi-directory=/boot --bootloader-id="{$menu[defkernel]}" --recheck ${work_disk}
					;;
				"*") 
					echo -e "Boot loader code not installed! Unsupported disklabel type: ${disklabeltype}"
					;;
			esac
			;;
		"uboot") 
			try mkimage -A arm -T script -C none -n "Boot.scr for android" -d boot.txt boot.scr
			;;
		"efimem") 
			try mkdir -vp ${work_dir}/boot/EFI/Boot
			try pv ${defkernel} > ${work_dir}/boot/EFI/Boot/bootx64.efi
			echo 'root=${root_part} add_efi_memmap -u initrd=${initramfs} ${kernelparams[defkernel]}' | iconv -f ascii -t ucs2 | efibootmgr -c -g -d ${work_disk} -p 1 -L '${menu[defkernel]}' -l '\EFI\Boot\bootx64.efi' -@ -
			;;
		*) ;;
	esac
fi

proceed_cleanup
exit 0
