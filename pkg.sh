 #!/bin/bash

CONFIG=/etc/pkg/pkg.conf
WORLD=/var/lib/pkg/world
FILES=/var/lib/pkg/files
PKGBUILDS=/usr/src/pkgbuilds

[ -f "$CONFIG" ] && source "$CONFIG"

cmd="$1"
pkg="$2"

patches() {
    for p in "${patch[@]}"; do
        file="/tmp/pkgs/$(basename "$p")"
        if [ -f "$file" ]; then
            echo "patch exists: $file"
        else
            echo "downloading patch: $(basename "$p")"
            wget -q -O "$file" "$p"
        fi
    done
}

confirmer() {
    local pkg="$1"
    # checks confirm flag!
    echo
    echo "build done for: $pkg"
    echo "please review before install."
    echo -n "install this package? [y/N]: "
    # reads 
    read -r reply
    # just cases 
    case "$reply" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            echo "install skipped, FUCCKKK" # usually bad, unless u was just testing
            return 1
            ;;
    esac
}

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
    # patch downloader! (for deps, anything really!) 
    patches

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
    
    # if there is a check() function in package build it does it 
    if declare -f check > /dev/null; then
      check
    fi

    # variable for installed 
    installed=false
    #confirm logic (only for important packages! (thats why the flag exists))
    if [ "$confirm" = "true" ]; then
        if confirmer "$name"; then
          install
          installed=true
        fi
    else
      install
      installed=true
    fi
    # install logic
    if [ "$installed" = "true" ]; then
      echo "$name $version" >> "$WORLD"
      echo "installed $name $version"
    else
      echo "installation skipped for $name" # not adding to world
    fi
    # done!!! wipe files:D 
    rm -rf /tmp/pkgs/$pkg 
    rm /tmp/pkgs/$pkg.tar 
    ;;

remove)
    [ "$(id -u)" -eq 0 ] || { echo "error: pkg must be run as root"; exit 1; }
    source "$PKGBUILDS/$pkg/pkgbuild"
    remove
    sed -i "/^$pkg /d" "$WORLD" # removes that pkg from world
    echo "removed $name $version"
    ;;

build)
    echo "building $pkg"
    # WORD!!
    [ "$(id -u)" -eq 0 ] || { echo "error: pkg must be run as root"; exit 1; }
    [ -z "$pkg" ] && echo "usage: pkg build <package>" && exit 1

    # i like having this part, makes me fell POWERFUL!!
    cat "$PKGBUILDS/$pkg/pkgbuild"

    # gets defs
    source "$PKGBUILDS/$pkg/pkgbuild"

   
    mkdir -p /tmp/pkgs
    # build does NOT do deps. simple.

    # now main pkg
    wget -O /tmp/pkgs/$pkg.tar "$source"

    mkdir -p /tmp/pkgs/$pkg # makes the pkg dir
  
    tar -xf /tmp/pkgs/$pkg.tar -C /tmp/pkgs/$pkg --strip-components=${strip:-1}
    # go into dir
    cd /tmp/pkgs/$pkg
    # yayy!!!
    build
    echo "built $name $version"
    echo "now doing checks (if they exist!)"
    if declare -f check > /dev/null; then
      check
    fi
    # if not, just end.
    # done!!! yay
    echo "now simply check /tmp/pkgs for the package, and what you want to do further/and or to install!"
    ;;

list)
    echo "installed packages:"
    cat "$WORLD"
    ;;
config)
    echo "MAKEFLAGS: $MAKEFLAGS, NINJAFLAGS: $NINJAFLAGS"
    ;;
*)
    echo "usage: pkg {install|remove|build|list} <package>"
    ;;

esac

