#!/bin/sh
# Builds one of the packages of this repository as the running distro's own package format: <package>/debian/
# on Debian and its derivatives, <package>/<package>.spec on Fedora. The LeechCraft CI images use it for the
# dependencies a distro ships older than LeechCraft needs.
#
# Usage: build.sh <package> <output directory>
#
# The packages to install land in the output directory itself, the debug symbol packages in its debug/
# subdirectory: an image has no use for them, a repository shipping these packages has.
# APT_TARGET_RELEASE=<suite> in the environment makes the Debian branch take its packages from that suite, as
# apt -t does, so that the library gets built against the same stack the image installs.
#
# <package>/package.conf is a shell fragment the script sources. It defines:
#   tarball_url <version>   a function printing the URL of the upstream tarball of that version
#   floor                   the version LeechCraft needs, for a package that stands in for the distro's own;
#                           unset for one the distro does not ship at all
#   debian_dev_package      the distro's development package the floor is checked against on Debian
#   fedora_dev_package      the same on Fedora
# With a floor, the script fails on purpose once the distro itself ships a version satisfying it: at that
# point the stage calling this script has to go, so the image goes back to testing the distro as it is.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
package=${1:?usage: build.sh <package> <output directory>}
out=${2:?usage: build.sh <package> <output directory>}
conf=$here/$package/package.conf
[ -f "$conf" ] || { echo "no such package here: $package ($conf missing)" >&2; exit 64; }
. "$conf"
. /etc/os-release

distro_caught_up()
{
	cat >&2 <<-MSG
		$PRETTY_NAME ships $package $1, which satisfies LeechCraft's requirement of >= $floor.
		Drop the $package stage from the Dockerfile of this image under tools/docker/base/ in the
		LeechCraft repository and install the distro's development package again.
	MSG
	exit 1
}

case " $ID ${ID_LIKE:-} " in
*' debian '*)
	changelog=$here/$package/debian/changelog
	source=$(sed -n '1s/^\([^ ]*\) .*/\1/p' "$changelog")
	# the upstream part of the version: what precedes the last hyphen, which starts the revision
	version=$(sed -n '1s/^[^ ]* (\(.*\)-[^-)]*).*/\1/p' "$changelog")
	target=${APT_TARGET_RELEASE:+-t $APT_TARGET_RELEASE}
	apt-get update
	if [ -n "${floor:-}" ]; then
		candidate=$(apt-cache $target policy "$debian_dev_package" | sed -n 's/^ *Candidate: //p')
		case $candidate in
			''|'(none)') ;;
			*) dpkg --compare-versions "$candidate" lt "$floor" || distro_caught_up "$candidate" ;;
		esac
	fi
	apt-get $target install -y --no-install-recommends build-essential ca-certificates curl
	mkdir -p /build && cd /build
	tarball=${source}_$version.orig.tar.gz
	curl -fsSL "$(tarball_url "$version")" -o "$tarball"
	tar xzf "$tarball"
	cd "$(tar tzf "$tarball" | sed -n '1s,/.*,,p')"
	cp -r "$here/$package/debian" .
	apt-get $target build-dep -y --no-install-recommends ./
	dpkg-buildpackage -b -us -uc -jauto
	mkdir -p "$out/debug"
	for f in ../*-dbgsym_*.deb; do
		if [ -e "$f" ]; then
			mv "$f" "$out/debug"
		fi
	done
	mv ../*.deb "$out"
	;;
*' fedora '*)
	spec=$here/$package/$package.spec
	version=$(sed -n 's/^Version:[[:space:]]*//p' "$spec")
	if [ -n "${floor:-}" ]; then
		candidates=$(dnf -q repoquery --latest-limit=1 --queryformat='%{version}\n' "$fedora_dev_package")
		candidate=$(printf '%s\n' $candidates | sort -V | tail -n 1)
		if [ -n "$candidate" ] && [ "$(printf '%s\n%s\n' "$floor" "$candidate" | sort -V | head -n 1)" = "$floor" ]; then
			distro_caught_up "$candidate"
		fi
	fi
	dnf install -y rpm-build dnf5-plugins
	command -v curl >/dev/null || dnf install -y curl
	mkdir -p ~/rpmbuild/SOURCES
	curl -fsSL "$(tarball_url "$version")" -o ~/rpmbuild/SOURCES/"$(basename "$(tarball_url "$version")")"
	dnf builddep -y "$spec"
	rpmbuild -bb "$spec"
	mkdir -p "$out/debug"
	find ~/rpmbuild/RPMS -name '*.rpm' | while read -r f; do
		case $f in
			*-debuginfo-*|*-debugsource-*) mv "$f" "$out/debug" ;;
			*) mv "$f" "$out" ;;
		esac
	done
	;;
*)
	echo "no packaging for $PRETTY_NAME here: build.sh knows Debian and Fedora and their derivatives" >&2
	exit 64
	;;
esac
