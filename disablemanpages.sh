#!/bin/sh
mainrepo="/var/overlay/gentoo/"
sed -i -e "s|*sys-apps/man-pages|-*sys-apps/man-pages|g" ${mainrepo}/profiles/default/linux/packages
chattr +i ${mainrepo}/profiles/default/linux/packages
sed -i -e "s|*virtual/man|-*virtual/man|g" ${mainrepo}/profiles/base/packages
chattr +i ${mainrepo}/profiles/base/packages