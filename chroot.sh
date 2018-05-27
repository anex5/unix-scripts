work_dir=$( dirname "${BASH_SOURCE[0]}" )
echo "Chrooting to ${work_dir}..."
mount -t proc none ${work_dir}/proc
mount --rbind /sys ${work_dir}/sys
mount --rbind /dev ${work_dir}/dev
mount --rbind /tmp ${work_dir}/tmp
#mount --rbind /usr/lib64 ${work_dir}/usr/lib64
env -i HOME=/root TERM=$TERM SHELL=/bin/bash chroot ${work_dir} /bin/bash --login
#umount ${work_dir}/usr/lib64
umount ${work_dir}/tmp
umount -l ${work_dir}/dev
umount -l ${work_dir}/sys
umount ${work_dir}/proc

