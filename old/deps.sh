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
    [ "$(id -u)" -eq 0 ] || { echo "error: pkg must be run as root"; exit 1; }
    [ -z "$pkg" ] && echo "usage: pkg install <package>" && exit 1
    grep -q "^$pkg " "$WORLD" && echo "$pkg is already installed" && exit 0
    
    # i like having this part
    cat "$PKGBUILDS/$pkg/pkgbuild"
    source "$PKGBUILDS/$pkg/pkgbuild"
    
    # now install! opsec 
    mkdir -p /tmp/pkgs
    # deps!!! 
    for dep in "${depends[@]}"; do
      if ! grep -q "^$dep " "$WORLD"; then
          echo "installing dependency: $dep"
          pkg install "$dep" # runs this script, also recurses! so if a dep has dep it auto does it!
      fi
    done

    # now main pkg
    wget -O /tmp/pkgs/$pkg.tar "$source"

    mkdir -p /tmp/pkgs/$pkg # makes the pkg dir
    # --strip-comp reduces risk of compile fucking itself :D
    tar -xf /tmp/pkgs/$pkg.tar -C /tmp/pkgs/$pkg --strip-components=${strip:-1} 
    # go into dir
    cd /tmp/pkgs/$pkg
    # yayy!!!
    build 
    install
    echo "$name $version" >> "$WORLD" # simple world file for pkg track!
    echo "installed $name $version"
    # done!!! 
    rm -rf /tmp/pkgs/$pkg 
    rm /tmp/pkgs/$pkg.tar 
    ;;

remove)
    [ "$(id -u)" -eq 0 ] || { echo "error: pkg must be run as root"; exit 1; }
    source "$PKGBUILDS/$pkg/pkgbuild"
    remove
    sed -i "/^$pkg /d" "$WORLD"
    echo "removed $name $version"
    ;;

build)
    echo "building $pkg"
     # safety first kids!
    [ "$(id -u)" -eq 0 ] || { echo "error: pkg must be run as root"; exit 1; }
    [ -z "$pkg" ] && echo "usage: pkg build <package>" && exit 1

    # i like having this part
    cat "$PKGBUILDS/$pkg/pkgbuild"

    # gets defs
    source "$PKGBUILDS/$pkg/pkgbuild"

    # now install! opsec
    mkdir -p /tmp/pkgs
    # build does NOT do deps. simple.

    # now main pkg
    wget -O /tmp/pkgs/$pkg.tar "$source"

    mkdir -p /tmp/pkgs/$pkg # makes the pkg dir
    # --strip-comp reduces risk of compile fucking itself :D
    tar -xf /tmp/pkgs/$pkg.tar -C /tmp/pkgs/$pkg --strip-components=${strip:-1}
    # go into dir
    cd /tmp/pkgs/$pkg
    # yayy!!!
    build
    echo "built $name $version"
    # done!!!
    echo "now simply check /tmp/pkgs for the package, and what you want to do further/and or to install!"
    ;;

list)
    echo "installed packages:"
    cat "$WORLD"
    ;;

*)
    echo "usage: pkg {install|remove|build|list} <package>"
    ;;

esac

