# LeechCraft packaging

Distro packaging that LeechCraft needs and no distro ships yet, in the distros' own formats, one directory per
source package:

- `qxmpp/`: Debian's and Fedora's packaging of [qxmpp](https://invent.kde.org/libraries/qxmpp), bumped to the
  version LeechCraft's Xoox plugin needs, for the CI images of the distros that ship an older one.

Each directory holds the packaging as the distro would have it, a `debian/` tree and a `.spec` file, plus a
`package.conf` with what `build.sh` needs to know about the package: where the upstream tarball comes from and,
for a package that stands in for the distro's own, the version LeechCraft needs and the names of the distro's
development packages.

`build.sh <package> <output directory>` builds a package in the running distro's own format, `.deb` on Debian
and its derivatives and `.rpm` on Fedora, and puts the packages to install into the output directory and the
debug symbol packages into its `debug/` subdirectory. It runs inside the distro, as root, and installs whatever
the build needs; the LeechCraft CI images run it in a throwaway stage of their Dockerfiles and install its
output. A package with a version floor makes the script fail on purpose once the distro itself ships a version
satisfying it: at that point the distro's own package is to be used again, and the packaging here retired.

## How the CI images use it

The Dockerfiles under `tools/docker/base` in the LeechCraft repository fetch this repository at the commit
named in `tools/packaging.ref` there, so a change here reaches the images only when that pin moves: push here,
then set the pin to the new commit.

## Bumping qxmpp

A new `debian/changelog` entry (version `X.Y.Z-0lcN`; the revision sorts below any Debian upload of the same
version), `Version`, `Release` and `%changelog` in `qxmpp.spec`, and, since qxmpp bumps its soname on every
minor release, `%global sover` and the `N` in the names of the `libqxmppqt6-N` and `libqxmppomemoqt6-N`
packages across `debian/control` and the install and lintian-overrides files. The floor in `package.conf`
mirrors the Xoox CMakeLists.

## Versions and releases

Versions sort below the distro's own uploads of the same upstream version, `-0lcN` on Debian and
`0.lcN%{?dist}` on Fedora, so a distro that catches up replaces these packages on upgrade. One `debian/` tree
and one spec serve every release of their family: a build for one release gets a changelog entry with a `~`
suffix (`1.17.0-0lc1~deb13u1`) prepended at build time, and the spec's `%{?dist}` does the same on Fedora.
Neither is needed for the CI images, which never share a repository.
