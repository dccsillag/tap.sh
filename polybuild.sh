#!/bin/sh

print_usage() {
    echo "Usage: $0 [-h] [-d] [<COMMAND> <additional options...>]"
    echo "==============================================================================="
    echo
    echo "-h                Show this help message and exit"
    echo
    echo "-s <BUILD_SYSTEM> Force a build system"
    echo "-d                Do a dry run"
    echo "-j                Number of jobs to use"
    echo
    echo "-m <MODE>         Build under a certain mode (options: debug, release,"
    echo "                  release+debug or optsize)"
    echo
    echo "Command (none = -B)"
    echo "-------------------"
    echo
    echo "-B                Build the project"
    echo "-C                Clean build files"
    echo "-I                Install executables"
    echo "-T                Run tests"
}

run_command() {
    echo \> "$*"
    # shellcheck disable=SC2068 # we want that $@ to split and become the command
    $@ > "$FIFO" 2>&1 &
    sed 's/^/|   /' < "$FIFO"
    wait $! || throw_error "tap failed" "on the following command:" "  $*"
}

throw_error() {
    echo "fatal error: $1"
    shift
    for _ in $(seq $#)
    do
        echo "!   $1"
        shift
    done
    exit 1
}

# Parse arguments
while getopts hBCITdj:s:m: name
do
    case $name in
        # Commands
        B) opt_command=build   ;;
        C) opt_command=clean   ;;
        I) opt_command=install ;;
        T) opt_command=test    ;;

        # Global options
        d) opt_dryrun=1              ;;
        s) opt_buildsystem="$OPTARG" ;;
        m) opt_mode="$OPTARG"        ;;
        j) opt_jobs="$OPTARG"        ;;

        # Help & fallback
        h) print_usage; exit 0 ;;
        ?) print_usage; exit 2 ;;
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
[ -z "$opt_jobs" ] && opt_jobs=1

# Figure out the build system, if necessary
if [ -z "$opt_buildsystem" ]
then
    if [ -f CMakeLists.txt ]
    then
        opt_buildsystem='cmake'
    elif [ -f Makefile ] || [ -f makefile ]
    then
        opt_buildsystem='make'
    else
        throw_error "couldn't deduce the build system"
    fi
fi

# Create temp stuff
trap 'rm -rf $TMPDIR' 0
TMPDIR=$(mktemp -d)
mkfifo "${FIFO=$TMPDIR/fifo}"

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
                    run_command make -j $opt_jobs
                fi
                ;;
            cmake)
                run_command mkdir -p .build-$opt_mode
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
                    run_command make -j $opt_jobs
                fi

                cd ..
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
    install)
        case "$opt_buildsystem" in
            make)
                if [ "$(id -u)" -ne 0 ]
                then
                    echo "NOT RUNNING AS ROOT -- installing to $HOME/.local/bin/"
                    [ -d "$HOME/.local/bin/" ] || throw_error "$HOME/.local/bin/ does not exist"
                    export PREFIX=~/.local
                fi

                if [ -n "$opt_dryrun" ]
                then
                    run_command make install -n
                else
                    run_command make install -j $opt_jobs
                fi
                ;;
            ?)
                throw_error "bad build system: $opt_buildsystem"
                ;;
        esac
        ;;
    test)
        case "$opt_buildsystem" in
            make)
                if [ -n "$opt_dryrun" ]
                then
                    run_command make test -n
                else
                    run_command make test
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
