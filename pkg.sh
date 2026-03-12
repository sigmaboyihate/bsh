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

#patchings!! (for fhs, etc, and just testing!)
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

verify() {
    if [ -n "$sha256sum" ]; then
        echo "verifying $pkg"
        echo "$sha256sum  /tmp/pkgs/$pkg.tar" | sha256sum -c || {
            echo "error: checksum failed for $pkg, aborting!!!"
            rm -f /tmp/pkgs/$pkg.tar
            exit 1
        }
    fi
    if [ -n "$md5sum" ]; then
        echo "verifying $pkg"
        echo "$md5sum  /tmp/pkgs/$pkg.tar" | md5sum -c || {
            echo "error: checksum failed for $pkg, aborting!!!"
            rm -f /tmp/pkgs/$pkg.tar
            exit 1
        }
    fi
    [ -z "$sha256sum" ] && [ -z "$md5sum" ] && echo "warn: no checksum for $pkg, living dangerously!! (chance fur malware! or bad shit, idk!)"
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
# revamped destdirinstall
destdirinstall() {
    mkdir -p /tmp/pkgs/$pkg-dest
    DESTDIR=/tmp/pkgs/$pkg-dest
    package

    # record files for removal tracking
    mkdir -p "$FILES"
    find /tmp/pkgs/$pkg-dest -type f -o -type l | \
        sed "s|/tmp/pkgs/$pkg-dest||" > "$FILES/$pkg"

    # copy to real system, atomic so no text file busy bs
    find /tmp/pkgs/$pkg-dest -type f -o -type l | while IFS= read -r f; do
        dest="${f#/tmp/pkgs/$pkg-dest}"
        mkdir -p "$(dirname "$dest")"
        cp -a "$f" "$dest.pkgnew" && mv "$dest.pkgnew" "$dest"
    done

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
    
    # now pkg
    wget -O /tmp/pkgs/$pkg.tar "$source"
    verify

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

    if declare -f postpackage > /dev/null; then
        postpackage
    fi # testing postpackage shit, probably just gonna configure basics for packages

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
    verify

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
 
rebuild) # install, but doesn't care about package being in world file
    [ "$(id -u)" -eq 0 ] || { echo "error: pkg must be run as root"; exit 1; }
    [ -z "$pkg" ] && echo "usage: pkg rebuild <package>" && exit 1

    pkgpath=$(findpkg "$pkg")
    [ -z "$pkgpath" ] && echo "error: no pkgbuild found for $pkg" && exit 1
    cat "$pkgpath/pkgbuild"
    source "$pkgpath/pkgbuild"

    mkdir -p /tmp/pkgs
    wget -O /tmp/pkgs/$pkg.tar "$source"
    verify
    mkdir -p /tmp/pkgs/$pkg
    tar -xf /tmp/pkgs/$pkg.tar -C /tmp/pkgs/$pkg --strip-components=${strip:-1}
    cd /tmp/pkgs/$pkg
    build

    if declare -f check > /dev/null; then check; fi

    destdirinstall

    # update world if already there, add if not
    sed -i "/^$pkg /d" "$WORLD"
    echo "$name $version" >> "$WORLD"
    echo "rebuilt $name $version"

    if declare -f postpackage > /dev/null; then postpackage; fi

    rm -rf /tmp/pkgs/$pkg
    rm -f /tmp/pkgs/$pkg.tar
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


update)
    [ "$(id -u)" -eq 0 ] || { echo "error: pkg must be run as root"; exit 1; }
    echo "checking for updates"
    updates=()
    # god finally! an update system!
    while IFS= read -r line; do
        p=$(echo "$line" | awk '{print $1}')
        iv=$(echo "$line" | awk '{print $2}')
        pp=$(findpkg "$p")
        [ -z "$pp" ] && echo "warn: no pkgbuild for $p" && continue
        pv=$(grep '^version=' "$pp/pkgbuild" | head -1 | cut -d= -f2 | tr -d '"'"'")
        [ "$iv" != "$pv" ] && echo "  $p: $iv -> $pv" && updates+=("$p") # very complex grep system
    done < "$WORLD"

    [ ${#updates[@]} -eq 0 ] && echo "everything up to date!!!" && exit 0

    echo -n "upgrade ${#updates[@]} package(s)? [y/N]: "
    read -r reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "cancelled."; exit 0 ;;
    esac

    for pkg in "${updates[@]}"; do
        echo "upgrading $pkg"
        sed -i "/^$pkg /d" "$WORLD"
        bash "$0" install "$pkg" || echo "failed: $pkg"
    done
    ;;
*)
    echo "usage: pkg {install|remove|build|list|config|requiredby|owns|update|rebuild} <package>"
    ;;

esac
