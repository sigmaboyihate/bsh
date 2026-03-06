 #!/bin/bash

CONFIG=/etc/pkg/pkg.conf
WORLD=/var/lib/pkg/world
FILES=/var/lib/pkg/files
PKGBUILDS=/usr/src/pkgbuilds

[ -f "$CONFIG" ] && source "$CONFIG"

cmd="$1"
pkg="$2"

case "$cmd" in

install)
    # safety first kids!
    [ -z "$pkg" ] && echo "usage: pkg install <package>" && exit 1
    grep -q "^$pkg " "$WORLD" && echo "$pkg is already installed" && exit 0
    
    # i like having this part
    echo "installing $pkg"
    cat "$PKGBUILDS/$pkg/pkgbuild"
    source "$PKGBUILDS/$pkg/pkgbuild"
    
    # now install! opsec 
    mkdir -p /tmp/pkgs
    wget -O /tmp/pkgs/$pkg.tar "$source"
    mkdir -p /tmp/pkgs/$pkg # makes the pkg dir
    # --strip-comp reduces risk of compile fucking itself :D
    #tar -xf /tmp/pkgs/$pkg.tar -C /tmp/pkgs/$pkg --strip-components=1
    tar -xf /tmp/pkgs/$pkg.tar -C /tmp/pkgs/$pkg --strip-components=${strip:-1} 
    # go into dir
    cd /tmp/pkgs/$pkg
    # yayy!!!
    build 
    install
    echo "$name $version" >> "$WORLD"
    echo "installed $name $version"
    # now... out! 
    rm -rf /tmp/pkgs/$pkg 
    rm /tmp/pkgs/$pkg.tar 
    ;;

remove)
    echo "removing $pkg"
    source "$PKGBUILDS/$pkg/pkgbuild"
    remove
    sed -i "/^$pkg /d" "$WORLD"
    echo "removed $name $version"
    ;;

build)
    echo "building $pkg"
    ;;

list)
    echo "installed packages:"
    cat "$WORLD"
    ;;

*)
    echo "usage: pkg {install|remove|build|list} <package>"
    ;;

esac

