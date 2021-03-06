#!/bin/bash

stage_name="stage3-latest.tar.xz"
stage_site="build.funtoo.org/funtoo-current/"
base_dir=$( dirname "${BASH_SOURCE[0]}" )
saved_file="$( basename "${BASH_SOURCE[0]}" ).prev"
tempfs="/mnt/tempfs/fsimage"
cfg_prefix="._cfg0000_"
local_overlay_name="local"

write_save=1
work_dir=
root_part=
boot_part=
swap_part=
tempfs_part=
hostname=
locales=
timezone=

source "$( dirname "${BASH_SOURCE[0]}" )/functions.sh"

printf "\nThis script helps to install funtoo"

execution_premission "Sure you want to run this? " || die

if [ -f "${saved_file}" ]; then
	saved_file="$(find ${base_dir} ~/* -name ${saved_file} -type f)"
	#echo ${saved_file}
	execution_premission "Continue previous installation?" && { source ${saved_file} || echo "" > ${saved_file}; }
	cleanup rm -r ${saved_file}
fi

part_list="$(get_partitions_list)"

#echo tempfs_part=${tempfs_part}
if ! [ -e "${tempfs_part}" ] || ! [ ${tempfs_part} == "skip" ]; then
	if execution_premission "Use virtual disk image? "; then
		echo
		read -p "Enter location of virtual disk image (default: ${tempfs})" tempfs

		options="${part_list}"
		if prompt_select "Select partition containing ${tempfs}."; then
			tempfs_part="${selected}"
			test ${write_save} && { save_var "tempfs_part" ${saved_file}; }
		fi
		echo "Mounting work partition ${tempfs%\/*}"
		try mkdir -p ${tempfs%\/*} && cleanup rm -r ${tempfs%\/*}
		try mount ${tempfs_part} ${tempfs%\/*} && { cleanup wait_umount ${tempfs%\/*}; cleanup umount ${tempfs%\/*}; }
		if [ ! -w ${tempfs} ]; then
			echo
			read -p "Enter size of new virtual disk image (M) " tempfs_size
			echo "Creating raw virtual disk image ${tempfs} of ${tempfs_size}M..."
			pv -EE -s ${tempfs_size}M -S -B 4k /dev/zero > ${tempfs} || echo "Cannot create virtual disk image ${tempfs} of ${tempfs_size}M"
		fi
		work_disk=$(losetup -f)
		try losetup -P ${work_disk} ${tempfs} && cleanup losetup -d ${work_disk}
	else
		tempfs_part="skip"
		test ${write_save} && { save_var "tempfs_part" ${saved_file}; }
	fi
fi

disk_list="$(lsblk -d -r | awk 'NR>1 { print $1 }') skip"

if ! [ -d "${work_dir}" ]; then
	fdisk -l
	options="${disk_list}"
	while execution_premission "Partition disks? "; do
		if prompt_select "Select disk for partitioning."; then
			work_disk="${selected}"
			test ${write_save} && { save_var "work_disk" ${saved_file}; }
			options="fdisk gdisk skip"
			if prompt_select "Select partitioning programm."; then
				try ${selected} ${work_disk}
			fi
		fi
	done
fi

#if [ -w "${tempfs}" ]; then
#	try kpartx -a -v ${tempfs} && cleanup kpartx -d ${tempfs}
#fi

part_list="$(get_partitions_list)" #reread partlist 

if ! [ -d "${work_dir}" ]; then
	options="$(find /mnt/* -maxdepth 0 -type d)"
	options="${options//${tempfs%\/*}/} new..."
	if prompt_select "Select directory you want to use as the installation mount point."; then
		case ${selected} in
			"new...") work_dir=$(prompt_new_dir /mnt);;
			*) work_dir=${selected};;
		esac
		test ${write_save} && { save_var "work_dir" ${saved_file}; }
	fi
fi

if ! [ -e "${root_part}" ]; then
	options="${part_list}"
	if prompt_select "Select root partition."; then
		root_part="${selected}"
		prompt_format ${selected}
		test ${write_save} && { save_var "root_part" ${saved_file}; }
	else
		die
	fi
fi

part_list="${part_list//${root_part}/}"

if ! [ -e "${boot_part}" ]; then
	if [ -n "${part_list//[[:cntrl:]]/}" ]; then
		options="${part_list} skip"
		if prompt_select "Select boot partition."; then
			boot_part="${selected}"
			execution_premission "Format boot partition? " && { try mkfs.vfat -F 32 ${boot_part}; }
		fi
		test ${write_save} && { save_var "boot_part" ${saved_file}; }
	fi
fi

#disk_list="$(find /dev/* -maxdepth 0 -name "sd?" -or -name "hd?")"
part_list="${disk_list//${root_part%[[:digit:]]*}/} ${part_list//${boot_part}/}"

if ! [ -e "${swap_part}" ]; then
	if [ -n "${part_list//[[:cntrl:]]/}" ]; then
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
! [ -e ${boot_part} ] && try mount ${boot_part} ${work_dir}/boot && { cleanup wait_umount ${work_dir}/boot; cleanup umount -d ${work_dir}/boot; }


if ! [ -f "${stage}" ]; then
	if execution_premission "Download new stage?"; then
		printf "\nLoading file list..."
		stage_list=$(wget -m -r -np -nd -e robots=off --spider -l4 -A ${stage_name} ${stage_site} 2>&1 | grep -Eio https\:\/\/.+${stage_name})
		#cleanup "rm -r ${stage_site}"
		options="${stage_list} skip"
		if prompt_select "Select stage to download."; then
			echo ${work_dir}/${selected##*\/}
			try download ${selected} ${work_dir} && { cleanup rm -r "${work_dir}/${selected##*\/}"; cleanup rm -r ~/.wget-hsts; cleanuo rm ~/index*.tmp; } || echo "Cannot download ${selected##*\/}"
			#try download "${selected}.DIGESTS.asc" ${work_dir} && cleanup rm -r "${work_dir}/${selected##*\/}.DIGESTS.asc" || echo "Cannot download ${selected##*\/}.DIGESTS.asc"
			#try download "${selected}.DIGESTS" ${work_dir} && cleanup rm -r "${work_dir}/${selected##*\/}.DIGESTS" || echo "Cannot download ${selected##*\/}.DIGESTS"
			try download ${selected}".hash.txt" ${work_dir} && cleanup rm -r "${work_dir}/${selected##*\/}.hash.txt" || echo "Cannot download ${selected}.hash.txt"

			#gpg --keyserver hkp://keys.gnupg.net --recv-keys 0xBB572E0E2D182910
			#gpg --verify ${work_dir}/${selected##*\/}.DIGESTS.asc
			echo "Verifing checksum..."
			try echo $(cat ${work_dir}/${selected##*\/}.hash.txt | awk -F'  ' '{ if ($1 ~ "SHA512") next; print $1; exit}') ${work_dir}/${selected##*\/} | sha256sum -c -
		fi
	fi
fi

stage_list=$(find / -maxdepth 5 -type f -name "${stage_name}")
if [ -n "${stage_list}" ]; then
	options="${stage_list} skip"
	if prompt_select "Select stage to extract."; then
		stage="${selected}"
		decrunch --xattrs-include='*.*' --numeric-owner ${stage} ${work_dir} || die "Cannot extract ${stage}"
		test ${write_save} && { save_var "stage" ${saved_file}; }
	fi
else
	if [ ! -x "${work_dir}/bin/bash" ]; then
		die "No ${stage_name} found on disk."
	fi
fi

template_list=$(find / ${base_dir} -maxdepth 2 -type f -name "*.template")
if [ -n "${template_list}" ]; then
	if execution_premission "Install templates files? "; then
		for file in ${template_list}
		do
			output=$(sed -n "1s|#||g;1 p" ${file})
			orig_file="${work_dir}${output//[[:cntrl:]][[:blank:]]/}"
			echo "${file} > ${orig_file}"
			output=$(sed -n "2,$ p" ${file})
			if [ $? -eq 0 ]; then
				if [ ! -d "${orig_file%\/*}" ]; then 
					if [ -e "${orig_file%\/*}" ] || [ -L "${orig_file%\/*}" ]; then 
						try rm ${orig_file%\/*} 
					fi
					try mkdir -p "${orig_file%\/*}"
				fi
				echo "${output}" > ${orig_file}
				[ -f "${orig_file}" ] || echo "Cannot write ${orig_file}"
			else
				echo "sed \"2,\$ p\" ${file} failed"
			fi
		done
		#repos_list="$(find ${work_dir}/etc/portage/repos.conf -type f )"
		#echo ${repos_list}
		#for file in ${repos_list}
		#do
		#	overlay_location=$(cat ${file} | awk -F= '{ if ($1 ~ "location") print $2}')
		#	echo ${overlay_location}
		#	if ! [ -d ${overlay_location} ]; then
		#		try mkdir -p ${overlay_location}
		#	fi
		#done
	fi
fi

if execution_premission "Edit config files? "; then

	if [ -z "${password}" ]; then
		read -p "Enter new password for root " password
		test ${write_save} && ! [ -z password ] && { save_var "password" ${saved_file}; }

	fi
	shadow="$(openssl passwd -1 ${password}):$(( $(date +%s)/86400 )):0:::::"
	sed -e "s|^\(root:\).*|\1"${shadow}"|" ${work_dir}/etc/shadow > ${work_dir}/etc/${cfg_prefix}shadow

	if [ -z "${hostname}" ]; then
		read -p "Enter hostname " hostname
		test ${write_save} && { save_var "hostname" ${saved_file}; }
	fi
	sed -e "s|^\(hostname=\).*|\1\""${hostname}"\"|" ${work_dir}/etc/conf.d/hostname > ${work_dir}/etc/conf.d/${cfg_prefix}hostname

	if execution_premission "Enable automatic root login?"; then
		if [ -z "${autologin}" ]; then
			test ${write_save} && { save_var "autologin" ${saved_file}; }
		fi
		sed -e "s|\bc1:12345:respawn:/sbin/agetty\b|& -a root|" ${work_dir}/etc/inittab > ${work_dir}/etc/${cfg_prefix}inittab
	fi

	zoneinfo="${work_dir}/usr/share/zoneinfo"
	if [ -z "${timezone}" ]; then
		options="$(find ${zoneinfo}/* -maxdepth 2 -type f ! -name "*.*" | sed -e "s|${zoneinfo}||g") skip"
		if prompt_select "Select timezone? "; then
			timezone=${selected}
			test ${write_save} && { save_var "timezone" ${saved_file}; }
		fi
	fi
	try ln -rsf /usr/share/zoneinfo${timezone} ${work_dir}/etc/localtime || echo "Cannot set timezone ${selected}"

	if [ -z "${hwclock}" ]; then
		options="UTC local skip"
		if prompt_select "Select hardware clock mode? "; then
			hwclock=${selected}
			test ${write_save} && { save_var "hwclock" ${saved_file}; }
		fi
	fi
	sed -e "s|^\(clock=\).*|\1\""${hwclock}"\"|" ${work_dir}/etc/conf.d/hwclock > ${work_dir}/etc/conf.d/${cfg_prefix}hwclock

	if [ -z "${locales}" ]; then
		cat ${work_dir}/etc/locale.gen > ${work_dir}/etc/${cfg_prefix}locale.gen
		while execution_premission "Add language? "; do
			options="$(cat ${work_dir}/usr/share/i18n/SUPPORTED | sed -e "s| UTF-8||g" | grep 'UTF-8') skip"
			if prompt_select "Select language? "; then
				locales+="${selected} "
			fi
		done
		test ${write_save} && { save_var "locales" ${saved_file}; }
	fi

	for locale in ${locales} 
	do
		echo "${locale} UTF-8" >> ${work_dir}/etc/${cfg_prefix}locale.gen
	done

	if [ -z "${keymap}" ]; then
		keymap_dir="${work_dir}/usr/share/keymaps"
		options="$(find ${keymap_dir}/* -maxdepth 3 -type f -name "*.map*" -printf "%f\n" | sed -e "s|.map.*||g" | sort) skip"
		if prompt_select "Select keymap? "; then
			keymap="${selected}"
		fi
		test ${write_save} && { save_var "keymap" ${saved_file}; }
	fi
	sed -e "s|^\(keymap=\).*|\1\""${keymap}"\"|" ${work_dir}/etc/conf.d/keymaps > ${work_dir}/etc/conf.d/${cfg_prefix}keymaps
	sed -e "s|^\(consolefont=\).*|\1\"ter-u16b\"|" ${work_dir}/etc/conf.d/consolefont > ${work_dir}/etc/conf.d/${cfg_prefix}consolefont
	if [ -a ${work_dir}/etc/runlevels/boot/consolefont ]; then
		ln -rs /etc/init.d/conslefont ${work_dir}/etc/runlevels/boot/consolefont
	fi

	fstabgen "${root_part}:/:defaults:0:1 ${boot_part}:/boot:noauto,noatime:1:2 ${swap_part}:swap:sw:0:0" "${work_dir}/etc/fstab"

	sed -e "s|^\(MAKEOPTS=\).*|\1\"-j"$(( $(nproc)+1 ))" --quiet\"|" ${work_dir}/etc/genkernel.conf > ${work_dir}/etc/${cfg_prefix}genkernel.conf
	sed -e "s|^\(MAKEOPTS=\).*|\1\"-j"$(( $(nproc)+1 ))" --quiet\"|" ${work_dir}/etc/portage/make.conf > ${work_dir}/etc/portage/${cfg_prefix}make.conf
	sed -i "s|^\(LINGUAS=\).*|\1\""${locales//_*/}"\"|" ${work_dir}/etc/portage/${cfg_prefix}make.conf
	sed -i "s|^\(L10N=\).*|\1\""${locales//_*/}"\"|" ${work_dir}/etc/portage/${cfg_prefix}make.conf
fi

if execution_premission "Enable dhcp network? "; then
	ln -rsf ${work_dir}/etc/init.d/netif.tmpl ${work_dir}/etc/init.d/net.eth0
	echo template=dhcpcd > ${work_dir}/etc/conf.d/${cfg_prefix}net.eth0
	ln -rsf ${work_dir}/etc/init.d/dhcpcd ${work_dir}/etc/runlevels/default/dhcpcd 
	cp /etc/resolv.conf ${work_dir}/etc/resolv.conf
	echo "nameserver 8.8.8.8" >> ${work_dir}/etc/resolv.conf
	echo "nameserver 8.8.4.4" >> ${work_dir}/etc/resolv.conf
fi

if execution_premission "Create blank local overlay? "; then
	echo
	read -p "Enter name of the local overlay (default: "${local_overlay_name}") " entered_overlay_name
	if [ -n "${entered_overlay_name}" ]; then 
		local_overlay_name=${entered_overlay_name} 
	fi

	mkdir -p ${work_dir}/var/overlay/${local_overlay_name}
	git clone https://github.com/funtoo/skeleton-overlay.git ${work_dir}/var/overlay/${local_overlay_name}
	echo ${local_overlay_name} > ${work_dir}/var/overlay/${local_overlay_name}/profiles/repo_name
	echo "masters = gentoo" >> ${work_dir}/var/overlay/${local_overlay_name}/metadata/layout.conf
	echo -e "[DEFAULT]/nmain-repo = gentoo/n["${local_overlay_name}"]\
	/nlocation = /var/overlay/${local_overlay_name}\
	/nauto-sync = no/npriority = 10/n" > ${work_dir}/etc/portage/repos.conf/${local_overlay_name}.conf
fi

if execution_premission "Remove /usr/share/{info,man,doc,gtk-doc} directories, and remove man packages from minimal system profile?"; then
	rm -r ${work_dir}/usr/share/{info,man,doc,gtk-doc}
	packages_path=${work_dir}/var/git/meta-repo/kits/core-kit/profiles/funtoo/1.0/linux-gnu/flavor/minimal/packages
	sed -i "s|^\(\*virtual/man\).*|\1\#\*virtual/man|" ${packages_path}
	sed -i "s|^\(\*sys-apps/man-pages\).*|\1\#\*sys-apps/man-pages|" ${packages_path}
	chattr +i ${packages_path}
fi

if execution_premission "Chroot in the new system environment? "; then
	try mount -t proc none ${work_dir}/proc && { cleanup wait_umount ${work_dir}/proc; cleanup umount ${work_dir}/proc; }
	try mount --rbind /sys ${work_dir}/sys && { cleanup umount -l ${work_dir}/sys; }
	try mount --rbind /dev ${work_dir}/dev && { cleanup umount -l ${work_dir}/dev; }

	profile="\
	etc-update; env-update && source /etc/profile \n\
	locale-gen; env-update && source /etc/profile \n\
	echo -e \"\nNow you are in chrooted environment.\
	\nselect default languge via eselect locale set\
	\nsync portage tree and merge packages you need\" \n\
	rm -rf ~/.bash_login"
	echo -e ${profile} > ${work_dir}/root/.bash_login
	chmod +x ${work_dir}/root/.bash_login
	env -i HOME=/root TERM=$TERM SHELL=/bin/bash chroot ${work_dir} /root/.bash_login
	env -i HOME=/root TERM=$TERM SHELL=/bin/bash chroot ${work_dir} /bin/bash --login
fi

proceed_cleanup
exit 0