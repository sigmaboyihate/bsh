#!/bin/bash
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
echo sudo!!!
mkdir -p /etc/pkg
mkdir -p /var/lib/pkg
mkdir -p /var/log/pkg
mkdir -p /usr/src/pkgbuilds
touch /var/lib/pkg/world
touch /etc/pkg/pkg.conf
touch /var/lib/pkg/deptree
mkdir -p /var/lib/pkg/files
# and also the files now!
cp -r pkgbuilds /usr/src # fixed dumbass error
cp pkg.sh /usr/bin/pkg
chmod +x /usr/bin/pkg
ln -svf /usr/bin/pkg /usr/bin/bsh
