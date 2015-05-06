#!/bin/bash

stage_name="stage3-latest.tar.xz"
stage_site="build.funtoo.org/funtoo-current/"
base_dir=$( dirname "${BASH_SOURCE[0]}" )
saved_file="$( basename "${BASH_SOURCE[0]}" ).prev"
tempfs="/mnt/tempfs/fsimage"
write_save=1
work_dir=""
root_part=""
boot_part=""
swap_part=""
step=0

source "$( dirname "${BASH_SOURCE[0]}" )/functions.sh"

printf "\nThis script helps to install funtoo"

execution_premission "Sure you want to run this? " || die
if [ -f ${saved_file} ]; then
	execution_premission "Continue previous installation?" && source ${saved_file} || echo "" > ${saved_file}
	cleanup rm -r ${saved_file}
fi

if ! [ -a "${work_disk}" ]; then
	fdisk -l
	options="$(find /dev/* -maxdepth 0 -name "sd?" -or -name "hd?")"
	if prompt_select "Select work disk."; then
		work_disk="${selected}"
		test ${write_save} && { save_var "work_disk" ${saved_file}; }
	fi

	if ! [ -a "${work_part}" ]; then
		if execution_premission "Use virtual disk image on work disk? "; then
			options="$(find "${work_disk%\/*}" -maxdepth 1 -name "${work_disk##*\/}?*")"
			if prompt_select "Select partition for ${tempfs}."; then
				work_part="${selected}"
				test ${write_save} && { save_var "work_part" ${saved_file}; }
			fi
			echo "Mounting work partition ${tempfs%\/*}"
			try mkdir -p ${tempfs%\/*} && cleanup rm -r ${tempfs%\/*}
			try mount ${work_part} ${tempfs%\/*} && { cleanup wait_umount ${tempfs%\/*}; cleanup umount ${tempfs%\/*}; }
			if [ ! -w ${tempfs} ]; then
				echo
				read -p "Enter size of new virtual disk image (M) " tempfs_size
				echo "Creating virtual disk image ${tempfs} of ${tempfs_size}M..."
				pv -EE -s ${tempfs_size}M -S -B 4k /dev/zero > ${tempfs} || echo "Cannot create virtual disk image ${tempfs} of ${tempfs_size}M"
			fi
			work_disk="/dev/loop1"
			try losetup ${work_disk} ${tempfs} && cleanup losetup -d ${work_disk}
			try kpartx -a -v ${tempfs} && cleanup kpartx -d ${tempfs}
			work_disk="/dev/mapper/loop1"
		fi
	fi

	options="fdisk gdisk skip"
	if prompt_select "Select partitioning programm."; then
		try ${selected} ${work_disk}
	fi
fi

if ! [ -d "${work_dir}" ]; then
	options="$(find /mnt/* -maxdepth 0 -type d) new..."
	if prompt_select "Select directory you want to use as the installation mount point."; then
		case ${selected} in
			"new...") work_dir=$(prompt_new_dir /mnt);;
			*) work_dir=${selected};;
		esac
		test ${write_save} && { save_var "work_dir" ${saved_file}; }
	fi
fi

part_list="$(find "${work_disk%\/*}" -maxdepth 1 -name "${work_disk##*\/}?*")"

if ! [ -a "${root_part}" ]; then
	options="${part_list}"
	if prompt_select "Select root partition."; then
		root_part="${selected}"
		prompt_format ${selected}
		test ${write_save} && { save_var "root_part" ${saved_file}; }
	else
		die
	fi
fi

if ! [ -a "${boot_part}" ]; then
	part_list="${part_list##*${root_part}}"
	if [ -n "${part_list}" ]; then
		options="${part_list} skip"
		if prompt_select "Select boot partition."; then
			boot_part="${selected}"
			execution_premission "Format boot partition? " && { try mkfs.vfat -F 32 ${boot_part}; }
		fi
		test ${write_save} && { save_var "boot_part" ${saved_file}; }
	fi
fi

if ! [ -a "${swap_part}" ]; then
	part_list="${part_list##*${boot_part}}"
	if [ -n "${part_list}" ]; then
		options="${part_list} skip"
		if prompt_select "Select swap partition."; then
			swap_part="${selected}"
			try mkswap ${swap_part}
			try swapon ${swap_part} && { cleanup swapoff ${swap_part}; }
			test ${write_save} && { save_var "swap_part" ${saved_file}; }
		fi
	fi
fi

printf "\nMounting partitions. \n"
try mount ${root_part} ${work_dir} && { cleanup wait_umount ${work_dir}; cleanup umount -d ${work_dir}; }
try mkdir -p ${work_dir}/boot
try mount ${boot_part} ${work_dir}/boot && { cleanup wait_umount ${work_dir}/boot; cleanup umount -d ${work_dir}/boot; }


if ! [ -f "${stage}" ]; then
	if execution_premission "Download new stage?"; then
		printf "\nLoading file list..."
		stage_list=$(wget -m -r -np -nd -e robots=off --spider -l4 -A ${stage_name} ${stage_site} 2>&1 | grep -Eio http.+${stage_name})
		#cleanup "rm -r ${stage_site}"
		options="${stage_list} skip"
		if prompt_select "Select stage to download."; then
			try download ${selected} ${work_dir} && cleanup rm -r "${work_dir}/${selected##*\/}" || echo "Cannot download ${selected}"
			try download ${selected}".hash.txt" ${work_dir} && cleanup rm -r "${work_dir}/${selected##*\/}.hash.txt" || echo "Cannot download ${selected}.hash.txt"
			try echo $(cat ${work_dir}/${selected##*\/}.hash.txt | awk '{ print $2 }') ${work_dir}/${selected##*\/} | sha256sum -c -
		fi
	fi
fi

if ! [ -x "${work_dir}/bin/bash" ]; then
	stage_list=$(find / -maxdepth 5 -type f -name "${stage_name}")
	if [ -n "${stage_list}" ]; then
		options="${stage_list} skip"
		if prompt_select "Select stage to extract."; then
			stage="${selected}"
			decrunch ${stage} ${work_dir} || die "Cannot extract ${stage}"
			test ${write_save} && { save_var "stage" ${saved_file}; }
		fi
	else
		die "No ${stage_name} found on disk."
	fi
fi

if [ -z "${password}" ]; then
	read -p "Enter new password for root " password
	echo "root:$(openssl passwd -1 ${password}):$(( $(date +%s)/86400 )):0:::::" >> ${work_dir}/etc/shadow
	test ${write_save} && { save_var "password" ${saved_file}; }
fi

if [ -z "${hostname}" ]; then
	read -p "Enter hostname " hostname
	echo ${hostname} >> ${work_dir}/etc/conf.d/hostname
	test ${write_save} && { save_var "hostname" ${saved_file}; }
fi

if [ -z "${timezone}" ]; then
	zoneinfo="${work_dir}/usr/share/zoneinfo"
	options="$(find ${zoneinfo}/* -maxdepth 2 -type f ! -name "*.*" | sed -e "s|${zoneinfo}||g") skip"
	if prompt_select "Select timezone? "; then
		timezone=${selected}
		try ln -sf ${zoneinfo}/${timezone} ${work_dir}/etc/localtime || echo "Cannot set timezone ${selected}"
		test ${write_save} && { save_var "timezone" ${saved_file}; }
	fi
fi

if [ -z "${locale}" ]; then
	options="$(cat /usr/share/i18n/SUPPORTED | sed -e "s| UTF-8||g" | grep 'UTF-8') skip"
	if prompt_select "Select language? "; then
		locale=${selected}
		echo "LANG=${locale}" >> ${work_dir}/etc/env.d/02locales
		echo "LANGUAGE=${locale}" >> ${work_dir}/etc/env.d/02locales
		echo "${locale} UTF-8" >> ${work_dir}/etc/locale.gen
		test ${write_save} && { save_var "locale" ${saved_file}; }
	fi
fi

if execution_premission "Install config files? "; then
	pv ${base_dir}/fstab.template > ${work_dir}/etc/fstab
	fstabgen "${root_part}:/:defaults:0:1 ${boot_part}:/boot:noauto,noatime:1:2 ${swap_part}:swap:sw:0:0" "${work_dir}/etc/fstab"
	pv ${base_dir}/make.conf.template > ${work_dir}/etc/portage/make.conf
	echo "MAKEOPTS=\"-j$(( $(nproc)+1 )) --quiet\"" >> ${work_dir}/etc/portage/make.conf
	echo "LINGUAS=\"en ${locale:0:2}\"" >> ${work_dir}/etc/portage/make.conf
	pv /etc/resolv.conf > ${work_dir}/etc/resolv.conf
fi

if execution_premission "Chroot in the new system environment? "; then
	try mount -t proc none ${work_dir}/proc && { cleanup wait_umount ${work_dir}/proc; cleanup umount ${work_dir}/proc; }
	try mount --rbind /sys ${work_dir}/sys && { cleanup umount -l ${work_dir}/sys; }
	try mount --rbind /dev ${work_dir}/dev && { cleanup umount -l ${work_dir}/dev; }

	env -i HOME=/root TERM=$TERM SHELL=/bin/bash
	try chroot ${work_dir} env-update && source /etc/profile
	printf "\nNow you are in chrooted environment.\n"
	try chroot ${work_dir} /bin/bash
	#try chroot ${work_dir} /bin/bash -c "export PS1=\"funtoo \$PS1\""
fi

proceed_cleanup
exit 0