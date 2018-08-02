#!/bin/bash

## DEVICE PASSTHROUGH

configfile=/etc/vfio-pci.cfg
vmname="windows10vm"

vfiobind() {
   dev="$1"
        vendor=$(cat /sys/bus/pci/devices/$dev/vendor)
        device=$(cat /sys/bus/pci/devices/$dev/device)
        if [ -e /sys/bus/pci/devices/$dev/driver ]; then
                echo $dev > /sys/bus/pci/devices/$dev/driver/unbind
        fi
        echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id
   
}


if ps -A | grep -q $vmname; then
   echo "$vmname is already running." &
   exit 1

else

   cat $configfile | while read line;do
   echo $line | grep ^# >/dev/null 2>&1 && continue
      vfiobind $line
   done

cp /usr/share/edk2.git/ovmf-x64/OVMF_VARS-pure-efi.fd /tmp/my_vars.fd

## VM INITIALISATION

qemu-system-x86_64 \
  -name $vmname,process=$vmname \
  -machine type=q35,accel=kvm \
  -cpu host,kvm=off \
  -smp 4,sockets=1,cores=4,threads=1 \
  -enable-kvm \
  -m 3G \
  -mem-path /run/hugepages/kvm \
  -mem-prealloc \
  -balloon none \
  -rtc clock=host,base=localtime \
  -vga qxk \
  -serial none \
  -parallel none \
  -soundhw hda \
  -device vfio-pci,host=01:00.0,multifunction=on \
  -device vfio-pci,host=01:00.1 \
  -drive if=pflash,format=raw,readonly,file=/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd \
  -drive if=pflash,format=raw,file=/tmp/my_vars.fd \
  -boot order=dc \
  -device virtio-scsi-pci,id=scsi \
  -drive id=disk0,if=virtio,cache=none,format=raw,file=<storage>.img \
  -drive file=<windows>.iso,id=isocd,format=raw,if=none -device scsi-cd,drive=isocd \
  -drive file=<virtio-win>.iso,id=virtiocd,format=raw,if=none -device ide-cd,bus=ide.1,drive=virtiocd \
  -netdev type=tap,id=net0,ifname=tap0,vhost=on \
  -device virtio-net-pci,netdev=net0,mac=00:16:3e:00:01:01

   exit 0
fi