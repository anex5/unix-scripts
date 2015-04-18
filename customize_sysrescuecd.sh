#!/bin/bash

work_dir="/mnt"
selected=""
step=0
msg=""
PROGIMG="${0}"
XIFS=$IFS
#IFS=$' '
clean_cmds=""

tempfs_dir="/mnt/media"
test -n "${1}" && tempfs_size=${1} || tempfs_size=4000
squashfs_name="sysrcd.dat"
squashfs_mountpoint="/livemnt/squashfs"
squashfs_dst="customcd/files"
portage_tree_name="portage-latest.tar.xz"

execution_premission()
{
	local AMSURE
	if [ -n "${1}" ] ; then
		read -n 1 -p "${1} (y/[a]): " AMSURE
	else
		read -n 1 AMSURE
	fi
	echo "" 1>&2
	if [ "${AMSURE}" = "y" ] ; then
		return 0
	else
		return 1
	fi
}

decrunch()
{
	test -n "$@" || { echo "${FUNCNAME[0]}: No params given"; return 1; }
	local params=($@)
	local params_count=${#params[*]}
	local src="${params[params_count-2]}"
	local dst="${params[params_count-1]}"
	#echo ${params} ${params_count} ${src} ${dst}
	local cmd=""
	if [ -f "${src}" ]; then
		case "${src}" in
			*.tar) cmd="tar -xp -C ${dst} ";;
            *.tar.bz2,*.tbz2) cmd="tar -xpj -C ${dst} ";;
            *.tar.gz,*.tgz) cmd="tar -xpz -C ${dst} ";;
            *.tar.xz) cmd="tar -xpJ -C ${dst} ";;
            *.bz2) cmd="bunzip2 > ${dst} ";;
            *.deb) cmd="ar x > {dst} ";;
            *.gz) cmd="gunzip > ${dst} ";;
            *.rar) cmd="unrar x ${dst} ";;
            *.rpm) cmd="rpm2cpio > ${dst} | cpio --quiet -i --make-directories ";;
            *.zip) cmd="unzip -d ${dst} ";;
            *.z) cmd="uncompress ${dst} ";;
            *.7z) cmd="7z x ${dst} ";;
            *) echo "${FUNCNAME[0]}:  ${src} cannot be extracted via extract"; return 1;;
		esac
		try pv ${src} | ${cmd}
		return $?
	else
		echo "${FUNCNAME[0]}: ${src} is not a valid file"
		return 1
	fi
}

copy_files()
{
	test -n "$@" || { echo "${FUNCNAME[0]}: No params given"; return 1; }
	local params=($@)
	local params_count=${#params[*]}
	local src="${params[params_count-2]}"
	local dst="${params[params_count-1]}"
	try "rsync -h -a -t ${src} ${dst}"
	return $?
}

make_dir()
{
	test -n "${1}" || { echo "${FUNCNAME[0]}: No params given"; return 1; }
	local dirname="${1}"

	if ! [ -d ${dirname} ]; then
		echo "Creating ${dirname}..."
		if try mkdir -p ${dirname}
		then
			cleanup "rm -r ${dirname}"
		else
			echo "Can't create directory ${dirname}"
			return 1
		fi
	else
		echo "Directory ${dirname} already exists."
		return 0
	fi
}

wait_umount()
{
	if [ -n "${1}" ]; then
		while $(mountpoint -q ${1}); do
			echo "Waiting for ${1} to unmount..."
			sleep 0.5
		done
	fi
}

do_mount()
{
	test -n "$@" || { echo "${FUNCNAME[0]}: No params given"; return 1; }
	local params=($@)
	local params_count=${#params[*]}
	local src="${params[params_count-2]}"
	local dst="${params[params_count-1]}"
	#echo ${params} ${params_count} ${src} ${dst}
	if is_mounted ${dst}
	then
		echo "${dst} allready mounted."
		return 0
	else
		if try mount $@
		then
			cleanup "wait_umount "${dst}
			cleanup "umount -d "${dst}
		else
			echo "${FUNCNAME[0]}: Can't mount ${src} to ${dst}"
			return 1
		fi
	fi
}

cleanup()
{
	test -n "$@" || { echo "${FUNCNAME[0]}: No params given"; return 1; }
	local cmd_ix=${#clean_cmds[*]}
	clean_cmds[$cmd_ix]=${1}
}

do_cleanup()
{
	execution_premission "Execute cleanup?" || exit 1
	local cmd_count=${#clean_cmds[*]}
	for cmd_ix in ${!clean_cmds[*]}
	do
		echo "${clean_cmds[cmd_count-cmd_ix-1]}"
		${clean_cmds[cmd_count-cmd_ix-1]}
	done
	sync
}

dialog()
{
	echo
	step=$((${step}+1))
	if [ -n "${1}" ]; then
		echo "${step}. ${msg}"
		select_options "${1} exit" || die
		if [ "${selected}" = "exit" ]; then
			die "Exiting..."
		fi
	else
		execution_premission "${step}. ${msg}" || die
	fi
}

select_options()
{
	local i
	test -n "${1}" || { echo "${FUNCNAME[0]}: No params given"; return 1; }

	local options=${1}
	select i in ${options}
	do
		selected=${i}
		break
	done

	return 0
}

check_dir()
{
	if ! [ -d "${1}" ]; then
		if [ -z "${2}" ]; then
			echo "Directory ${1} doesn't exist."
			return 0
		else
			#echo "${2}" 1>&2
			return 1
		fi
	fi
}

is_mounted()
{
	test -n "${1}" || { echo "${FUNCNAME[0]}: No params given"; return 1; }
	if cat /proc/mounts | grep -q "${1}"
	then
		return 0
	else
		return 1
	fi
}

die()
{
	if [ -n "${1}" ]; then
		echo "$(basename ${PROGIMG}): ${1}"
	else
		echo "$(basename ${PROGIMG}): aborting."
	fi

	do_cleanup
	IFS=$XIFS
	exit 1
}

try()
{
	echo $@
	$@
	return $?
}

freespace()
{
	test -n "$@" || { echo "${FUNCNAME[0]}: No params given"; return 1; }
	echo $(df -m -P ${1} | grep " ${1}$" | tail -n 1 | awk '{print $4}')
	return $?
}

do_squashfs()
{
	local squashfs_exclude="${squashfs_dst}/usr/portage ${squashfs_dst}/var/cache/ ${squashfs_dst}/proc ${squashfs_dst}/dev ${squashfs_dst}/sys"
	test -n "${1}" && local squashfs_outdir="${1}" || local squashfs_outdir=${work_dir}

	if [ "$(freespace ${squashfs_outdir})" -lt 400 ]; then
		echo "${FUNCNAME[0]}: Not enough room in ${squashfs_outdir}"
		return 1
	fi

	# check that the files have been extracted
	if [ "$(ls -A ${squashfs_dst}/ 2>/dev/null | wc -l)" -eq 0 ]; then
		echo "${FUNCNAME[0]}: ${squashfs_dst} is empty, your must extract the files first."
		return 1
	fi

	# check that there are no remaining filesystems mounted
	for curfs in proc; do
		local curpath="${squashfs_dst}/${curfs}"
		local dircnt="$(ls -A ${curpath} 2>/dev/null | wc -l)"
		if [ ${dircnt} -gt 0 ]; then
			echo "${FUNCNAME[0]}: The directory ${curpath} must be empty"
			return 1
		fi
	done

	try "mksquashfs ${squashfs_dst}/ ${squashfs_outdir}/${squashfs_name} -e ${squashfs_exclude}" || echo "${FUNCNAME[0]}: mksquashfs: failed with code $?"; return 1

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
	if [ "$(freespace ${iso_outdir})" -gt 500 ]; then
		echo "Not enough room in ${iso_outdir}"
		return 1
	fi

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

msg="Sure you want to run this? "
dialog

if ! check_dir ${work_dir}
then
	if execution_premission "Create ${work_dir}?" ; then
		make_dir ${work_dir} || die
	else
		die "Work directory not selected"
	fi
fi

msg="Select directory you want to use for temporary image."
dir_list=$(find ${work_dir}/* -maxdepth 0 -type d)
dialog "${dir_list} new..."
	if [ "${selected}" = "new..." ] ; then
		read -p "Enter name of new directory" new_dir
		make_dir "/mnt/${new_dir}"
	else
		work_dir=${selected}
	fi

fdisk -l

msg="Select working partition."
part_list=$(find /dev/* -maxdepth 0 -name "sd??*" -or -name "hd??*")
dialog "${part_list}"

	tempfs="${tempfs_dir}/fsimage"
	work_part="${selected}"

	make_dir ${tempfs_dir}

	echo "Mount the working partition. ${work_part}"
	do_mount "${work_part} ${tempfs_dir}"

	if ! [ -f "${tempfs}" ]; then
		echo "Creating filesystem container ${tempfs} of ${tempfs_size}M..."
		try "dd if=/dev/zero of=${tempfs} bs=1M count=${tempfs_size}" || echo "Cannot create filesystem container ${tempfs} of ${tempfs_size}M"
		echo "Formatting..."
		try "mkfs.btrfs -m single ${tempfs}" || echo "Cannot format ${tempfs}"
	fi

	do_mount "-o loop ${tempfs} ${work_dir}"

squashfs_dst="${work_dir}/${squashfs_dst}"

msg="Select source squashfs image? "
squashfs_src=$(find / -maxdepth 5 -size +200M -type f -name ${squashfs_name} -or -name *.squashfs)
if [ -n "${squashfs_src}" ]; then
	dialog "${squashfs_src} skip"
	if ! [ "${selected}" = "skip" ]; then
		make_dir "${squashfs_mountpoint}"
		squashfs_src="${selected}"
		do_mount "-t squashfs -o loop ${selected} ${squashfs_mountpoint}"
		make_dir "${squashfs_dst}"
		copy_files "${squashfs_mountpoint}/ ${squashfs_dst}" || echo "Cannot copy the files from ${selected}"
	fi
else
	echo "No squashfs found on disk."
fi

msg="Download new portage tree?"

snapshot_list="http://ftp.osuosl.org/pub/funtoo/funtoo-current/snapshots/${portage_tree_name} \
http://mirror.yandex.ru/gentoo-distfiles/snapshots/${portage_tree_name} \
http://gentoo.osuosl.org/snapshots/${portage_tree_name}"

if [ -n "${snapshot_list}" ]; then
	dialog "${snapshot_list} skip"
	if ! [ "${selected}" = "skip" ]; then
		try "curl --progress-bar -o ${work_dir}/${portage_tree_name} ${selected}" || echo "Cannot download new portage tree from ${selected}"
		cleanup "rm -r ${work_dir}/${portage_tree_name}"
	fi
else
	echo "Using snapshots found on disk."
fi

msg="Extract new portage tree? "
snapshot_list=$(find / -maxdepth 5 -type f -name "portage-*.tar.*")
if [ -n "${snapshot_list}" ]; then
	dialog "${snapshot_list} skip"
	if ! [ "${selected}" = "skip" ]; then
		decrunch "${selected} ${squashfs_dst}/usr/" || echo "Cannot extract the files from the ${selected}"
		cleanup "rm -r ${squashfs_dst}/usr/portage"
	fi
else
	echo "No snapshots found on disk."
fi

msg="Chroot in the sysresccd environment? "
dialog
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


msg="Select directory you want to use for output ${squashfs_name}."
dir_list=$(find /mnt -maxdepth 2 -type d)
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
