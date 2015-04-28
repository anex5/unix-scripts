#!/bin/bash

stage_name="stage3-latest.tar.xz"
stage_site="build.funtoo.org/funtoo-current/"
saved_file="$( basename "${BASH_SOURCE[0]}" ).prev"
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
fi

if ! [ -a "${work_disk}" ]; then
	fdisk -l
	options="$(find /dev/* -maxdepth 0 -name "sd?" -or -name "hd?")"
	if prompt_select "Select work disk."; then
		work_disk="${selected}"
		test ${write_save} && { save_var "work_disk" ${saved_file}; }
	fi

	options="fdisk gdisk skip"
	if prompt_select "Select partitioning programm."; then
		try ${selected} ${work_disk}
	fi
fi

if ! [ -d "${work_dir}" ];then
	options="$(find /mnt/* -maxdepth 0 -type d) new..."
	if prompt_select "Select directory you want to use as the installation mount point."; then
		case ${selected} in
			"new...") work_dir=$(prompt_new_dir /mnt);;
			*) work_dir=${selected};;
		esac
		test ${write_save} && { save_var "work_dir" ${saved_file}; }
	fi
fi

part_list="$(find "${work_disk%????}" -maxdepth 1 -name "${work_disk: -3}?")"

if ! [ -a "${root_part}" ]; then
	options="${part_list}"
	if prompt_select "Select root partition."; then
		root_part="${selected}"
		if execution_premission "Format root partition? "; then
			options=$(find /sbin/* /usr/sbin/* -maxdepth 0 -name "mkfs.*")
			if prompt_select "Select filesystem"; then
				try "${selected}"
				read -p "Enter additional params " params
				try "${selected} ${params} ${root_part}"
			fi
		fi
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
		if prompt_select -m "Select swap partition." -o "${part_list} skip"; then
			swap_part="${selected}"
			try mkswap ${swap_part}
			try swapon ${swap_part} && { cleanup swapoff ${swap_part}; }
			test ${write_save} && { save_var "swap_part" ${saved_file}; }
		fi
	fi
fi

printf "Mounting partitions. \n"
try mount ${root_part} ${work_dir} && { cleanup wait_umount ${work_dir}; cleanup umount ${work_dir}; }
try mkdir -p ${work_dir}/boot
try mount ${boot_part} ${work_dir}/boot && { cleanup wait_umount ${work_dir}/boot; cleanup umount ${work_dir}/boot; }

if ! [ -f "${stage}" ]; then
	if execution_premission "Download new stage?"; then
		printf "\nLoading file list..."
		stage_list=$(wget -r -np --spider -l6 -A ${stage_name} ${stage_site} 2>&1 | grep -Eio http.+${stage_name})
		cleanup "rm -r ${stage_site}"
		options="${stage_list} skip"
		if prompt_select "Select stage to download."; then
			try curl --progress-bar -L -o ${work_dir}/${stage_name} -C - ${selected} && cleanup rm -r ${work_dir}/${stage_name}
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

if execution_premission "Chroot in the new system environment? "; then
	try mount -t proc none ${work_dir}/proc && { cleanup wait_umount ${work_dir}/proc; cleanup umount ${work_dir}/proc; }
	try mount --rbind /sys ${work_dir}/sys && { cleanup wait_umount ${work_dir}/sys; cleanup umount ${work_dir}/sys; }
	try mount --rbind /dev ${work_dir}/dev && { cleanup wait_umount ${work_dir}/dev; cleanup umount ${work_dir}/dev; }
	try scp /etc/resolv.conf ${work_dir}/etc/
	env -i HOME=/root TERM=$TERM
	printf "\nNow you are in chrooted environment.\n"
	try chroot ${work_dir} env-update && source /etc/profile; /bin/bash
	#try chroot ${work_dir} /bin/bash -c "export PS1=\"funtoo \$PS1\""
fi

proceed_cleanup
exit 0