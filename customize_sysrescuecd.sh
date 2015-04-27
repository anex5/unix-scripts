#!/bin/bash

work_dir="/mnt"
selected=""
step=0
msg=""
PROGIMG="${0}"
XIFS=$IFS
#IFS=$' '
clean_cmds=""

tempfs_dir="/mnt/tempfs/fsimage"
test -n "${1}" && tempfs_size=${1} || tempfs_size=4000
squashfs_name="sysrcd.dat"
squashfs_mountpoint="/livemnt/squashfs"
squashfs_dst="customcd/files"
portage_tree_name="portage-latest.tar.xz"

do_squashfs()
{
	local squashfs_exclude="${squashfs_dst}/usr/portage ${squashfs_dst}/var/cache/ ${squashfs_dst}/proc ${squashfs_dst}/dev ${squashfs_dst}/sys"
	test -n "${1}" && local squashfs_outdir="${1}" || local squashfs_outdir=${work_dir}

	[ "$(freespace ${squashfs_outdir})" -lt 400 ] && { echo "${FUNCNAME[0]}: Not enough room in ${squashfs_outdir}"; return 1; }

	# check that the files have been extracted
	[ "$(ls -A ${squashfs_dst}/ 2>/dev/null | wc -l)" -eq 0 ] && { echo "${FUNCNAME[0]}: ${squashfs_dst} is empty, your must extract the files first.";	return 1; }

	# check that there are no remaining filesystems mounted
	for curfs in proc; do
		local curpath="${squashfs_dst}/${curfs}"
		local dircnt="$(ls -A ${curpath} 2>/dev/null | wc -l)"
		if [ ${dircnt} -gt 0 ]; then
			echo "${FUNCNAME[0]}: The directory ${curpath} must be empty"
			return 1
		fi
	done

	try "mksquashfs ${squashfs_dst}/ ${squashfs_outdir}/${squashfs_name} -e ${squashfs_exclude}"

	md5sum ${squashfs_outdir}/${squashfs_name} > ${squashfs_outdir}/${squashfs_name%????}.md5

	# Change permissions to allow the file to be sent by thttpd for PXE-boot
	chmod 666 ${squashfs_outdir}/${squashfs_name}
}

do_isogen()
{
	curtime="$(date +%Y%m%d-%H%M)"
	ISO_VOLUME="SYSRESCCD"
	test -n "${1}" && local iso_outdir="${1}" || local iso_outdir="${work_dir}"

	# check for free space
	[ "$(freespace ${iso_outdir})" -lt 500 ] && { echo "Not enough room in ${iso_outdir}"; return 1 }

	# ---- copy critical files and directories
	for curfile in version isolinux
	do
		copy_files "/livemnt/boot/${curfile} ${iso_outdir}" || echo "${FUNCNAME[0]}: cannot copy ${curfile} to ${iso_outdir}"
	done

	# ---- copy optionnal files and directories
	for curfile in boot bootprog bootdisk efi ntpasswd usb_inst usb_inst.sh usbstick.htm
	do
		copy_files "/livemnt/boot/${curfile} ${iso_outdir}" || echo "${FUNCNAME[0]}: cannot copy ${curfile} to ${iso_outdir} (non critical error, maybe be caused by \"docache\")"
	done

	if [ ! -d "${iso_outdir}/isolinux" ]; then
		echo "${FUNCNAME[0]}: you must create a squashfs filesystem before making iso"
		return 1
	fi

	# Set keymap in isolinux.cfg
	if ! [ -z ${KEYMAP} ]; then
		echo "Keymap to be loaded: ${KEYMAP}"
		copy_files "${iso_outdir}/isolinux/isolinux.cfg ${iso_outdir}/isolinux/isolinux.bak"
		sed -i -r -e "s: setkmap=[a-z0-9]+::g ; s:APPEND:APPEND setkmap=${KEYMAP}:gi" ${iso_outdir}/isolinux/isolinux.cfg
	fi

	echo "Volume name of the CDRom: ${ISO_VOLUME}"

	try "xorriso -as mkisofs -joliet -rock \
		-omit-version-number -disable-deep-relocation \
		-b isolinux/isolinux.bin -c isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		-eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
		-o ${iso_outdir}/sysresccd-${curtime}.iso \
		-volid ${ISO_VOLUME} ${iso_outdir}" || echo "${FUNCNAME[0]}: mkisofs failed"; return 1

	md5sum ${iso_outdir}/sysresccd-${curtime}.iso > ${iso_outdir}/sysresccd-${curtime}.md5

	echo "Final ISO image: ${iso_outdir}/sysresccd-${curtime}.iso"
}


echo
echo "This script helps to customize sysrescuecd."

printf "\n\nThis script helps to customize sysrescuecd."

let step+=1
execution_premission "${step}. Sure you want to run this? " || die

#execution_premission "Create ${work_dir}?" && { mkdir -p ${work_dir} || die } || { die "Work directory not selected" }

let step+=1; printf "\n${step}. Select directory you want to use as the installation mount point."
dir_list=$(find /mnt/* -maxdepth 0 -type d)
if select_options "${dir_list} new..."; then
	if [ "${selected}" = "new..." ] ; then
		read -p "Enter name of new directory " new_dir
		try mkdir -p "/mnt/${new_dir}"
		work_dir="/mnt/${new_dir}"
	else
		work_dir=${selected}
	fi
else
	die
fi

fdisk -l

part_list=$(find /dev/* -maxdepth 0 -name "sd??*" -or -name "hd??*")
let step+=1; printf "\n${step}. Select work partition."
if select_options "${part_list}"; then
	work_part="${selected}"

	if execution_premission "Format work partition? "; then
		mkfs=$(find /sbin/* /usr/sbin/* -maxdepth 0 -name "mkfs.*")
		if select_options "${mkfs}"; then
			try ${selected}
			echo
			read -p "Enter additional params " params
			try ${selected} ${params} ${work_part}
		fi
	fi

	if execution_premission "Create filesystem container on work partition? "; then
		echo "Mount work partition. ${tempfs%/*}"
		try mount ${work_part} ${tempfs%/*}
		cleanup wait_umount ${tempfs%/*}
		cleanup umount -d ${tempfs%/*}
		read -p "Enter size of new container " tempfs_size
		echo "Creating filesystem container ${tempfs} of ${tempfs_size}M..."
		try dd if=/dev/zero of=${tempfs} bs=1M count=${tempfs_size} || echo "Cannot create filesystem container ${tempfs} of ${tempfs_size}M"
		try mount -o loop ${tempfs} ${work_dir}
	else
		echo "Mount work partition. ${work_part}"
		try mount ${work_part} ${work_dir}
	fi
	cleanup "wait_umount "${work_dir}
	cleanup "umount -d "${work_dir}

else
	die
fi

squashfs_dst="${work_dir}/${squashfs_dst}"
squashfs_src=$(find / -maxdepth 5 -size +200M -type f -name ${squashfs_name} -or -name *.squashfs)
if [ -n "${squashfs_src}" ]; then
	let step+=1; printf "\n${step}. Select source squashfs image "
	if select_options "${stage_list} skip"; then
		try mkdir "${squashfs_mountpoint}"
		squashfs_src="${selected}"
		try mount -t squashfs -o loop ${selected} ${squashfs_mountpoint}
		try mkdir -p ${squashfs_dst}
		rsync -ah --delete ${squashfs_mountpoint}/ ${squashfs_dst} || echo "Cannot copy the files from ${selected}"
	fi
else
	echo "No squashfs found on disk."
fi

msg="Download new portage tree?"

snapshot_list="http://ftp.osuosl.org/pub/funtoo/funtoo-current/snapshots/${portage_tree_name} \
http://mirror.yandex.ru/gentoo-distfiles/snapshots/${portage_tree_name} \
http://gentoo.osuosl.org/snapshots/${portage_tree_name}"

if [ -n "${snapshot_list}" ]; then
	let step+=1; printf "\n${step}. Download new portage tree? "
	if select_options "${snapshot_list} skip"; then
		try "curl --progress-bar -o ${work_dir}/${portage_tree_name} ${selected}" || echo "Cannot download new portage tree from ${selected}"
		cleanup "rm -r ${work_dir}/${portage_tree_name}"
	fi
else
	echo "Using snapshots found on disk."
fi

snapshot_list=$(find / -maxdepth 5 -type f -name "portage-*.tar.*")
if [ -n "${snapshot_list}" ]; then
	let step+=1; printf "\n${step}. Extract new portage tree? "
	if select_options "${snapshot_list} skip"; then
		decrunch "${selected} ${squashfs_dst}/usr/" || echo "Cannot extract the files from the ${selected}"
		cleanup "rm -r ${squashfs_dst}/usr/portage"
	fi
else
	echo "No snapshots found on disk."
fi

if execution_premission "Chroot in the sysresccd environment? "; then
	make_dir ${squashfs_dst}/proc
	make_dir ${squashfs_dst}/dev
	make_dir ${squashfs_dst}/sys
	do_mount "-o bind /proc ${squashfs_dst}/proc"
	do_mount "-o bind /dev ${squashfs_dst}/dev"
	do_mount "-o bind /sys ${squashfs_dst}/sys"

	echo "Now you are in chrooted environment."
	echo "You can emerge some packages as usual."

	#cp -L /etc/resolv.conf ${squashfs_dst}/etc/
	chroot ${squashfs_dst} /bin/bash -c "env-update; source /etc/profile; gcc-config \$(gcc-config -c); "
	chroot ${squashfs_dst} /bin/bash
	chroot ${squashfs_dst} /bin/bash -c "sysresccd-cleansys devtools; rm -rf /var/log/* /usr/sbin/sysresccd-* /usr/share/sysreccd"
fi

dir_list=$(find /mnt -maxdepth 2 -type d)
if [ -n "${dir_list}" ]; then
	let step+=1; printf "\n${step}. Select directory you want to use for output ${squashfs_name}. "

	dialog "${dir_list} new..."
	if [ "${selected}" = "new..." ]; then
		read -p "Enter name of new directory in /mnt " new_dir
		make_dir "/mnt/${new_dir}"
		output=/mnt/${new_dir}
	else
		output=${selected}
	fi

msg="Create new ${squashfs_name}?"
dialog
	umount -d ${squashfs_dst}/proc
	do_squashfs ${output}

msg="Select default keymap"
keymaps=$(find /livemnt/boot/isolinux/maps/* -maxdepth 0 -type f -name "*.ktl" -printf "%f\n" | sed -e "s!.ktl!!g")
dialog "${keymaps}"
	KEYMAP=${selected}

msg="Select directory you want to use for output iso."
dir_list=$(find /mnt -maxdepth 2 -type d)
dialog "${dir_list} new..."
	if [ "${selected}" = "new..." ]; then
		read -p "Enter name of new directory in /mnt " new_dir
		make_dir "/mnt/${new_dir}"
		output=/mnt/${new_dir}
	else
		output=${selected}
	fi

msg="Create new ISO image?"
dialog
	do_isogen ${output}

do_cleanup
exit 0
