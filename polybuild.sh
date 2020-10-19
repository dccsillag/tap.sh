#!/bin/sh

usage() {
    echo "Usage: $0 [-h] [-d] [<COMMAND> <additional options...>]"
    echo "==============================================================================="
    echo
    echo "-h                Show this help message and exit"
    echo
    echo "-s <BUILD_SYSTEM> Force a build system"
    echo "-d                Do a dry run"
    echo
    echo "-m <MODE>         Build under a certain mode (options: debug, release,"
    echo "                  release+debug or optsize)"
    echo
    echo "Command (none = -B)"
    echo "-------------------"
    echo
    echo "-B                Build the project"
    echo "-C                Clean build files"
}

run_command() {
    echo \> "$*"
    $@ 2>&1 | sed 's/^/    /'
    # [ -z "$opt_dryrun" ] && $@
}

throw_error() {
    echo "fatal error: $*"
    exit 1
}

# Parse arguments
while getopts hBCds:m: name
do
    case $name in
        # Commands
        B) opt_command=build ;;
        C) opt_command=clean ;;

        # Global options
        d) opt_dryrun=1 ;;
        s) opt_buildsystem="$OPTARG" ;;
        m) opt_mode="$OPTARG" ;;

        # Help & fallback
        h) usage; exit 0 ;;
        ?) usage; exit 2 ;;
    esac
done
shift $((OPTIND-1))

if [ "$#" -ge 1 ]
then
    echo "Extra arguments: $*"
    exit 2
fi

# Default arguments
[ -z "$opt_command" ] && opt_command=build
[ -z "$opt_mode" ] && opt_mode=debug

# Figure out the build system, if necessary
if [ -z "$opt_buildsystem" ]
then
    if [ -f CMakeLists.txt ]
    then
        opt_buildsystem=cmake
    elif [ -f Makefile ] || [ -f makefile ]
    then
        opt_buildsystem=make
    else
        throw_error "couldn't deduce the build system"
    fi
fi

# Do stuff:
case "$opt_command" in
    build)
        case "$opt_buildsystem" in
            make)
                case $opt_mode in
                    # As suggested in https://stackoverflow.com/a/59314670/4803382
                    debug)         export CFLAGS="$CFLAGS -O0 -g"              ;;
                    release)       export CFLAGS="$CFLAGS -O3 -DNDEBUG"        ;;
                    release+debug) export CFLAGS="$CFLAGS -O2 -DNDEBUG -g"     ;;
                    optsize)       export CFLAGS="$CFLAGS -Os -DNDEBUG"        ;;
                    ?)             throw_error "unknown build mode: $opt_mode" ;;
                esac

                if [ -n "$opt_dryrun" ]
                then
                    run_command make -n
                else
                    run_command make
                fi
                ;;
            cmake)
                run_command mkdir -p .build-$opt_mode
                pushd
                run_command cd .build-$opt_mode
                case $opt_mode in
                    debug)         run_command cmake .. -DCMAKE_BUILD_TYPE=Debug          ;;
                    release)       run_command cmake .. -DCMAKE_BUILD_TYPE=Release        ;;
                    release+debug) run_command cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo ;;
                    optsize)       run_command cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel     ;;
                    ?)             throw_error "unknown build mode: $opt_mode"            ;;
                esac

                if [ -n "$opt_dryrun" ]
                then
                    run_command make -n
                else
                    run_command make
                fi

                popd
                ;;
            ?)
                throw_error "bad build system: $opt_buildsystem"
                ;;
        esac
        ;;
    clean)
        case "$opt_buildsystem" in
            make)
                if [ -n "$opt_dryrun" ]
                then
                    run_command make clean -n
                else
                    run_command make clean
                fi
                ;;
            ?)
                throw_error "bad build system: $opt_buildsystem"
                ;;
        esac
        ;;
    ?)
        echo "Unknown command: $opt_command"
        exit 2
        ;;
esac
