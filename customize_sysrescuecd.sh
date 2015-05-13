#!/bin/bash

work_dir="/mnt"
selected=""
step=0
PROGIMG="${0}"
XIFS=$IFS
#IFS=$' '
clean_cmds=""

tempfs="/mnt/tempfs/fsimage"
test -n "${1}" && tempfs_size=${1} || tempfs_size=4000
squashfs_name="sysrcd.dat"
squashfs_mountpoint="/livemnt/squashfs"
squashfs_dst="customcd/files"
portage_tree_name="portage-latest.tar.xz"

source "$( dirname "${BASH_SOURCE[0]}" )/functions.sh"

do_squashfs()
{
	local squashfs_exclude="${squashfs_dst}/usr/portage ${squashfs_dst}/var/cache/ ${squashfs_dst}/proc ${squashfs_dst}/dev ${squashfs_dst}/sys"
	test $# -gt 0 && local squashfs_outdir="${1}" || local squashfs_outdir=${work_dir}

	[ "$(freespace ${squashfs_outdir})" -lt 400 ] && { echo "${FUNCNAME[0]}: Not enough room in ${squashfs_outdir}"; return 1; }

	# check that the files have been extracted
	[ "$(ls -A ${squashfs_dst}/ 2>/dev/null | wc -l)" -eq 0 ] && { echo "${FUNCNAME[0]}: ${squashfs_dst} is empty, your must extract the files first.";	return 1; }

	# check that there are no remaining filesystems mounted
	for curfs in proc; do
		local curpath="${squashfs_dst}/${curfs}"
		local dircnt="$(ls -A ${curpath} 2>/dev/null | wc -l)"
		[ ${dircnt} -gt 0 ] && { echo "${FUNCNAME[0]}: The directory ${curpath} must be empty";	return 1; }
	done

	try mksquashfs ${squashfs_dst}/ ${squashfs_outdir}/${squashfs_name} -e ${squashfs_exclude}

	md5sum ${squashfs_outdir}/${squashfs_name} > ${squashfs_outdir}/${squashfs_name%????}.md5

	# Change permissions to allow the file to be sent by thttpd for PXE-boot
	chmod 666 ${squashfs_outdir}/${squashfs_name}
}

do_isogen()
{
	curtime="$(date +%Y%m%d-%H%M)"
	ISO_VOLUME="SYSRESCCD"
	test $# -gt 0 && local iso_outdir="${1}" || local iso_outdir="${work_dir}"

	# check for free space
	[ "$(freespace ${iso_outdir})" -lt 500 ] && { echo "Not enough room in ${iso_outdir}"; return 1; }

	# ---- copy critical files and directories
	for curfile in version isolinux
	do
		scp "/livemnt/boot/${curfile} ${iso_outdir}" || { echo "${FUNCNAME[0]}: cannot copy ${curfile} to ${iso_outdir}"; return 1; }
	done

	# ---- copy optionnal files and directories
	for curfile in boot bootprog bootdisk efi ntpasswd usb_inst usb_inst.sh usbstick.htm
	do
		scp "/livemnt/boot/${curfile} ${iso_outdir}" || echo "${FUNCNAME[0]}: cannot copy ${curfile} to ${iso_outdir} (non critical error, maybe be caused by \"docache\")"
	done

	[ -d "${iso_outdir}/isolinux" ] || { echo "${FUNCNAME[0]}: you must create a squashfs filesystem before making iso"; return 1; }

	# Set keymap in isolinux.cfg
	if [ -n "${KEYMAP}" ]; then
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
		-volid ${ISO_VOLUME} ${iso_outdir}" || { echo "${FUNCNAME[0]}: mkisofs failed"; return 1; }

	md5sum ${iso_outdir}/sysresccd-${curtime}.iso > ${iso_outdir}/sysresccd-${curtime}.md5

	echo "Final ISO image: ${iso_outdir}/sysresccd-${curtime}.iso"
}

printf "\nThis script helps to customize sysrescuecd.\n"

execution_premission "Sure you want to run this? " || die

#execution_premission "Create ${work_dir}?" && { mkdir -p ${work_dir} || die } || { die "Work directory not selected" }

options="$(find /mnt/* -maxdepth 0 -type d) new..."
if prompt_select "Select directory you want to use." ; then
	case ${selected} in
		"new...") work_dir=$(prompt_new_dir /mnt);;
		*) work_dir=${selected};;
	esac
else
	die
fi

fdisk -l

options=$(find /dev/* -maxdepth 0 -name "sd??*" -or -name "hd??*")
if prompt_select "Select work partition."; then
	work_part="${selected}"
	if execution_premission "Use filesystem container on work partition? "; then
		echo "Mounting work partition ${tempfs%\/*}"
		try mkdir -p ${tempfs%\/*} && cleanup rm -r ${tempfs%\/*}
		try mount ${work_part} ${tempfs%\/*} && { cleanup wait_umount ${tempfs%\/*}; cleanup umount -d ${tempfs%\/*}; }
		if [ ! -w ${tempfs} ]; then
			echo
			read -p "Enter size of new container (M) " tempfs_size
			echo "Creating filesystem container ${tempfs} of ${tempfs_size}M..."
			pv -EE -s ${tempfs_size}M -S -B 4k /dev/zero > ${tempfs} || echo "Cannot create filesystem container ${tempfs} of ${tempfs_size}M"
			options=$(find /sbin/* /usr/sbin/* -maxdepth 0 -name "mkfs.*")
			if prompt_select "Select filesystem"; then
				${selected}
				read -p "Enter additional params " params
				try ${selected} ${params} ${tempfs}
			fi
		fi
		echo "Mounting filesystem container ${tempfs}"
		try mount -o loop ${tempfs} ${work_dir} && { cleanup wait_umount ${work_dir}; cleanup umount -d ${work_dir}; }
	else
		#if execution_premission "Format work partition? "; then
		#fi
		echo "Mounting work partition ${work_part}"
		try mount ${work_part} ${work_dir} && { cleanup wait_umount ${work_dir}; cleanup umount -d ${work_dir}; }
	fi
else
	die
fi

squashfs_dst="${work_dir}/${squashfs_dst}"
squashfs_src=$(find / -maxdepth 5 -size +200M -type f -name ${squashfs_name} -or -name *.squashfs)
if [ -n "${squashfs_src}" ]; then
	options="${squashfs_src} skip"
	if prompt_select "Select source squashfs image: "; then
		try mkdir "${squashfs_mountpoint}"
		squashfs_src="${selected}"
		try mount -t squashfs -o loop ${selected} ${squashfs_mountpoint}
		try mkdir -p ${squashfs_dst}
		rsync -atiH ${squashfs_mountpoint}/* ${squashfs_dst} | pv -s $(df -i ${squashfs_mountpoint} | tail -n 1 | awk '{print $3}') > /dev/null || echo "Cannot copy the files from ${selected}"
	fi
else
	echo "No squashfs found on disk."
fi

snapshot_list="http://ftp.osuosl.org/pub/funtoo/funtoo-current/snapshots/${portage_tree_name} \
http://mirror.yandex.ru/gentoo-distfiles/snapshots/${portage_tree_name} \
http://gentoo.osuosl.org/snapshots/${portage_tree_name}"

if [ -n "${snapshot_list}" ]; then
	options="${snapshot_list} skip"
	if prompt_select "Select new portage tree to download? "; then
		try curl --progress-bar -L -o ${work_dir}/${portage_tree_name} -C - ${selected} && { cleanup rm -r ${work_dir}/${portage_tree_name}; } || echo "Cannot download new portage tree from ${selected}"
	fi
else
	echo "Using snapshots found on disk."
fi

snapshot_list=$(find / -maxdepth 5 -type f -name "portage-*.tar.*")
if [ -n "${snapshot_list}" ]; then
	options="${snapshot_list} skip"
	if prompt_select "Extract new portage tree? "; then
		decrunch "${selected}" "${squashfs_dst}/usr/" && cleanup rm -r ${squashfs_dst}/usr/portage || echo "Cannot extract the files from the ${selected}"
	fi
else
	echo "No snapshots found on disk."
fi

if execution_premission "Chroot in the sysresccd environment? "; then
	try mkdir -p ${squashfs_dst}/proc
	try mkdir -p ${squashfs_dst}/dev
	try mkdir -p ${squashfs_dst}/sys
	try mount -o bind /proc ${squashfs_dst}/proc
	try mount -o bind /dev ${squashfs_dst}/dev
	try mount -o bind /sys ${squashfs_dst}/sys

	echo "Now you are in chrooted environment."
	echo "You can emerge some packages as usual."

	#scp -L /etc/resolv.conf ${squashfs_dst}/etc/
	try chroot ${squashfs_dst} env-update; source /etc/profile; gcc-config $(gcc-config -c); /bin/bash
	try chroot ${squashfs_dst} sysresccd-cleansys devtools; rm -rf /var/log/* /usr/sbin/sysresccd-* /usr/share/sysreccd
fi

if execution_premission "Create new ${squashfs_name}?"; then
	dir_list=$(find /mnt/* -maxdepth 1 -type d)
	if [ -n "${dir_list}" ]; then
		options="${dir_list} new..."
		if prompt_select "Select directory you want to use for output ${squashfs_name}. "; then
			case ${selected} in
				"new...") output=$(prompt_new_dir /mnt);;
				*) output=${selected};;
			esac
		else
			die
		fi
	fi

	try umount ${squashfs_dst}/proc
	wait_umount ${squashfs_dst}/proc
	do_squashfs ${output}

	if execution_premission "Create new ISO image?"; then
		options=$(find /livemnt/boot/isolinux/maps/* -maxdepth 0 -type f -name "*.ktl" -printf "%f\n" | sed -e "s!.ktl!!g")
		if prompt_select "Select default keymap"; then
			KEYMAP=${selected}
		fi

		options="$(find /mnt/* -maxdepth 1 -type d) new..."
		if prompt_select "Select directory you want to use for output iso."; then
			case ${selected} in
				"new...") output=$(prompt_new_dir /mnt);;
				*) output=${selected};;
			esac
		fi

		do_isogen ${output}
	fi
fi

proceed_cleanup
exit 0