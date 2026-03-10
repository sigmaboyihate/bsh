#!/bin/bash
# files will still have 'pkg' instead of 'bsh' because i am lazy.
CONFIG=/etc/pkg/pkg.conf
WORLD=/var/lib/pkg/world
FILES=/var/lib/pkg/files
PKGBUILDS=/usr/src/pkgbuilds
DESTDIR=/tmp/pkgs/$pkg-dest # destdir, its initialized twice but idc
DEPTREE=/var/lib/pkg/deptree # for dependencies (requiredby)

[ -f "$CONFIG" ] && source "$CONFIG"

cmd="$1"
pkg="$2"
pkg=$(echo "$2" | tr '[:upper:]' '[:lower:]') # fix for many

# so i can organize /usr/src/pkgbuilds
findpkg() {
    find "$PKGBUILDS" -type d -iname "$1" | head -1
}
#patching, since im on lfs i need fhs patches 
patches() {
    for p in "${patch[@]}"; do
        patchfile="/tmp/pkgs/$(basename "$p")"
        if [ ! -f "$patchfile" ]; then
            echo "downloading patch: $(basename "$p")"
            wget -q -O "$patchfile" "$p"
        fi
        if [ -d "/tmp/pkgs/$pkg" ]; then
            echo "applying patch: $(basename "$p")"
            patch -Np1 -i "$patchfile"
        fi
    done
}

# purely there just for you to glance around and see if glibc did all tests right (other pkgs too)
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
            echo "install skipped, FUCCKKK" # usually bad, unless u was just testing, and yes, i swear in official code
            return 1
            ;;
    esac
}

# installs to destdir first, and lets me track for removal easier (used to remove via pkgbuild files, hella inefficent, fallback still exists) 
destdirinstall() {
    mkdir -p /tmp/pkgs/$pkg-dest
    DESTDIR=/tmp/pkgs/$pkg-dest package # destdir!!

    # record files to shove them into file tracking for removal thingy
    mkdir -p "$FILES"
    find /tmp/pkgs/$pkg-dest -type f -o -type l | \
        sed "s|/tmp/pkgs/$pkg-dest||" > "$FILES/$pkg"

    # copy to real system
    cp -r /tmp/pkgs/$pkg-dest/* /

    # cleanup stage
    rm -rf /tmp/pkgs/$pkg-dest
}

case "$cmd" in

install)
    # safety first kids!
    [ "$(id -u)" -eq 0 ] || { echo "error: pkg must be run as root"; exit 1; }
    [ -z "$pkg" ] && echo "usage: pkg install <package>" && exit 1
    if grep -iq "^$pkg " "$WORLD"; then
        echo "package already installed: $pkg"
        exit 0
    fi
    LOCKDIR=/tmp/pkgs/locks
    mkdir -p "$LOCKDIR"
    if [ -f "$LOCKDIR/$pkg" ]; then
         echo "error: circular dependency detected for $pkg"
         exit 1
    fi
    touch "$LOCKDIR/$pkg"
    trap 'rm -f "$LOCKDIR/$pkg"' EXIT # so script will remove lockdir if it fucks up mid install
    
    
    # i like having this part
    pkgpath=$(findpkg "$pkg")
    [ -z "$pkgpath" ] && echo "error: no pkgbuild found for $pkg" && exit 1
    cat "$pkgpath/pkgbuild"
    source "$pkgpath/pkgbuild"
    # now install! opsec
    mkdir -p /tmp/pkgs
    # patch downloader! (for deps, anything really!)
    # conflict checker
    for conflict in "${conflicts[@]}"; do
        if grep -q "^$conflict " "$WORLD"; then
            echo "error: $pkg conflicts with $conflict (installed)"
            exit 1
        fi
    done
    patches

    # deps!!!
    for dep in "${depends[@]}"; do
        if ! grep -q "^$dep " "$WORLD"; then
            echo "installing dependency: $dep"
            bash "$0" install "$dep" # runs this script, also recurses! so if a dep has dep it auto does it!
        fi
        echo "$(echo "$dep" | tr '[:upper:]' '[:lower:]') $pkg" >> "$DEPTREE"
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

    # if there is a check() function in pkgbuild it does it
    if declare -f check > /dev/null; then
        check
    fi

    # variable for installed
    installed=false
    # confirm logic (only for important packages! (thats why the flag exists))
    if [ "$confirm" = "true" ]; then
        if confirmer "$name"; then
            destdirinstall
            installed=true
        fi
    else
        destdirinstall
        installed=true
    fi

    # install logic
    if [ "$installed" = "true" ]; then
        echo "$name $version" >> "$WORLD"
        echo "installed $name $version"
    else
        echo "installation skipped for $name" # not adding to world
    fi

    # done!!! wipe files :D
    rm -rf /tmp/pkgs/$pkg
    rm -f /tmp/pkgs/$pkg.tar
    rm -f "$LOCKDIR/$pkg"
    ;;

remove)
    # WARNING!!! IF YOU INSTALLED GLIBC AND SHIT, YES - RUNNING SUDO PKG REMOVE BINUTILS WILL INDEED REMOVE BINUTILS, BE CAREFUL!
    [ "$(id -u)" -eq 0 ] || { echo "error: pkg must be run as root"; exit 1; }
    [ -z "$pkg" ] && echo "usage: pkg remove <package>" && exit 1
    grep -q "^$pkg " "$WORLD" || { echo "$pkg is not installed"; exit 1; }

    force=false
    [ "$3" = "--force" ] && force=true

    pkgpath=$(findpkg "$pkg")
    [ -z "$pkgpath" ] && echo "error: no pkgbuild found for $pkg" && exit 1
    source "$pkgpath/pkgbuild"

    if [ "$force" = "false" ]; then
        requiredby=$(grep "^$pkg " "$DEPTREE" | awk '{print $2}' | tr '\n' ' ')
        if [ -n "$requiredby" ]; then
            echo "error: $pkg is required by: $requiredby"
            exit 1
        fi
    fi
    # remove all tracked files
    while IFS= read -r file; do
        rm -f "$file"
    done < "$FILES/$pkg"

    rm -f "$FILES/$pkg" # removes the package file, just for cleanup
    sed -i "/^$pkg /d" "$WORLD" # removes that pkg from world

    sed -i "/ $pkg$/d" "$DEPTREE"   # remove entries where package is the dependent
    sed -i "/^$pkg /d" "$DEPTREE"   # remove entries where package is the dependency
    echo "removed $name $version"
    ;;

build)
    echo "building $pkg"
    # WORD!!
    [ "$(id -u)" -eq 0 ] || { echo "error: pkg must be run as root"; exit 1; }
    [ -z "$pkg" ] && echo "usage: pkg build <package>" && exit 1

    # i like having this part, makes me feel POWERFUL!!
    pkgpath=$(findpkg "$pkg")
    [ -z "$pkgpath" ] && echo "error: no pkgbuild found for $pkg" && exit 1
    cat "$pkgpath/pkgbuild"
    source "$pkgpath/pkgbuild"
    # gets defs

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
    # holy simple 
    echo "installed packages:"
    cat "$WORLD"
    ;;

requiredby)
    # also for debugging, lets me see what package is requiredby what, good for debugging problems
    [ -z "$pkg" ] && echo "usage: pkg requiredby <package>" && exit 1
    result=$(grep "^$pkg " "$DEPTREE" | awk '{print $2}')
    [ -z "$result" ] && echo "$pkg is not required by anything" && exit 0
    echo "$pkg is required by:"
    echo "$result"
    ;;

config)
    # simply shows what you source from config. /etc/pkg/pkg.conf
    echo "MAKEFLAGS: $MAKEFLAGS, NINJAFLAGS: $NINJAFLAGS"
    ;;

owns)
    # for debug
    file="$2"
    [ -z "$file" ] && echo "usage: pkg owns <file>" && exit 1
    result=$(grep -rl "^$file$" "$FILES")
    [ -z "$result" ] && echo "no package owns $file" && exit 1
    echo "owned by: $(basename $result)"
    ;;
*)
    echo "usage: pkg {install|remove|build|list|config|requiredby|owns} <package>"
    ;;

esac
