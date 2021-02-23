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
    echo "-R                Build and run an executable"
    echo "-C                Clean build files"
    echo "-I                Install executables"
    echo "-T                Run tests"
    # TODO: profile (-P)
    echo "-M                Run benchmarks (measure)"
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

bad_command() {
    throw_error "Bad command for build system '$opt_buildsystem': '$opt_command'"
}

bad_build_mode() {
    throw_error "Bad build mode for build system '$opt_buildsystem': '$opt_mode'"
}

# Parse arguments
while getopts hBR:CITMdj:s:m: name
do
    case $name in
        # Commands
        B) opt_command='build'                    ;;
        R) opt_command='run'; opt_torun="$OPTARG" ;;
        C) opt_command='clean'                    ;;
        I) opt_command='install'                  ;;
        T) opt_command='test'                     ;;
        M) opt_command='benchmark'                ;;

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

if [ "$#" -ge 1 ] && [ "$opt_command" = run ]
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
    elif [ -f meson.build ]
    then
        opt_buildsystem='meson'
    else
        throw_error "couldn't deduce the build system"
    fi
fi

# Create temp stuff
trap 'rm -rf $TMPDIR' 0
TMPDIR=$(mktemp -d)
mkfifo "${FIFO=$TMPDIR/fifo}"

# Do stuff:

[ "$opt_command" = install ] && {
    if [ "$(id -u)" -ne 0 ]; then
        echo "NOT RUNNING AS ROOT -- installing to $HOME/.local/bin/"
        [ -d "$HOME/.local/bin/" ] || throw_error "$HOME/.local/bin/ does not exist"
        export PREFIX=~/.local
    else
        export PREFIX=/usr/local
    fi
}

case "$opt_buildsystem" in
    make)
        [ -n "$opt_dryrun" ] && opt_dryrun=-n
        case "$opt_command" in
            build)
                case "$opt_mode" in
                    # As suggested in https://stackoverflow.com/a/59314670/4803382
                    debug)         export CFLAGS="$CFLAGS -O0 -g"              ;;
                    release)       export CFLAGS="$CFLAGS -O3 -DNDEBUG"        ;;
                    release+debug) export CFLAGS="$CFLAGS -O2 -DNDEBUG -g"     ;;
                    optsize)       export CFLAGS="$CFLAGS -Os -DNDEBUG"        ;;
                    *)             bad_build_mode                              ;;
                esac

                run_command make "$opt_dryrun" -j "$opt_jobs"
                ;;
            run)
                ./"$opt_torun" $@
                ;;
            install)
                run_command make install "$opt_dryrun" -j "$opt_jobs"
                ;;
            clean)
                run_command make clean "$opt_dryrun" -j "$opt_jobs"
                ;;
            test)
                run_command make test "$opt_dryrun" -j "$opt_jobs"
                ;;
            benchmark)
                run_command make bench "$opt_dryrun" -j "$opt_jobs"
                ;;
            *) bad_command ;;
        esac
        ;;
    cmake)
        case "$opt_command" in
            build)
                run_command mkdir -p .build-$opt_mode
                run_command cd .build-$opt_mode
                cd .build-$opt_mode || exit 1 # we need to do this outside run_command
                                              # because we need to change the cwd
                case $opt_mode in
                    debug)         run_command cmake .. -DCMAKE_BUILD_TYPE=Debug          ;;
                    release)       run_command cmake .. -DCMAKE_BUILD_TYPE=Release        ;;
                    release+debug) run_command cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo ;;
                    optsize)       run_command cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel     ;;
                    *)             bad_build_mode                                         ;;
                esac

                if [ -n "$opt_dryrun" ]
                then
                    run_command make -n
                else
                    run_command make -j $opt_jobs
                fi

                cd ..
                ;;
            *) bad_command ;;
        esac
        ;;
    meson)
        case "$opt_command" in
            build)
                case $opt_mode in
                    debug)         btype=debug                                   ;;
                    release)       btype=release                                 ;;
                    release+debug) btype=debugoptimized                          ;;
                    optsize)       throw_error "no optsize build type for Meson" ;;
                    *)             bad_build_mode                                ;;
                esac
                test -d build || run_command meson setup --buildtype=$btype build .

                run_command meson compile -C build -j $opt_jobs
                ;;
            run)
                build/"$opt_torun" $@
                ;;
            install)
                run_command meson configure -D prefix=$PREFIX build # FIXME
                run_command meson install -C build
                ;;
            clean)
                run_command meson compile -C build --clean
                ;;
            *) bad_command ;;
        esac
        ;;
    *) throw_error "bad build system: $opt_buildsystem" ;;
esac
