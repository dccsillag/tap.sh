Tap
===

Tap is a tool for easily building your projects (mainly those written in C/C++).

Make has its flaws, but it still outshines most other build systems (namely
CMake and Meson, which are quite mainstream) in its user interface for us
people who make the shell their home -- just run `make`. No need to create
a build directory, run some command and _then_ run `make`/`ninja` _in the build
directory_.

So, Tap is a layer of abstraction over the mess that is C/C++ build systems,
providing a uniform interface very much like the one provided by `make`. See
the [Usage](#usage) section for examples.

Usage
-----

### Build the project

```
tap
```

or

```
tap -B
```

You can also specify build modes, as such:

```
tap -m <MODE>
```

The following modes are available:

- `debug` (not optimized, with assertions, with debug symbols)
- `release` (optimized, without assertions, without debug symbols)
- `release+debug` (optimized, without assertions, with debug symbols)
- `optsize` (optimized for size, without assertions, without debug symbols)

### Clean build files

```
tap -C
```

### Install the built binaries

```
tap -I
```

If you run with `sudo`, then the binaries will be installed to the path
proposed by the underlying build system. However, if `tap -I` is not run as
root then binaries will be installed to `~/.local/bin/`.

Installation
------------

Just run the install script (or copy the `polybuild.sh` script to somewhere in your `$PATH` yourself).

```
./install.sh
```

or

```
sudo ./install.sh
```
