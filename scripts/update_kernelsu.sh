#!/bin/bash
set -e -o pipefail
exec 9>.kernelsu-fetch-lock
flock -n 9 || exit 0
[[ $(( $(date +%s) - $(stat -c %Y "drivers/kernelsu/.check" 2>/dev/null || echo 0) )) -gt 86400 ]] || exit 0

# KernelSU-Next "legacy" branch: the one for non-GKI kernels with manual hooks.
# (releases/latest and the default branch are GKI only)
AUTHOR="KernelSU-Next"
REPO="KernelSU-Next"

# Newest vX.Y.Z-legacy tag, also used as KSU_VERSION_TAG
LATEST_TAG=$(git ls-remote --tags --refs "https://github.com/$AUTHOR/$REPO" 'v*-legacy' | sed 's@.*refs/tags/@@' | sort -V | tail -n1)
if [[ -z "$LATEST_TAG" ]]; then
	echo "ERROR: Could not get the KernelSU-Next legacy tags" >&2
	[[ -d drivers/kernelsu ]] && touch drivers/kernelsu/.check
	exit 1
fi

#LATEST COMMIT
REF="legacy"
#LATEST RELEASE (v3.4.0-legacy does not build on 4.14: it calls strscpy_pad(), fixed on the branch since)
#REF="$LATEST_TAG"
#HARDCODED COMMIT
#REF="b933b1f728116a456fbebf27b6a8772a640cdf23"

# Commit count of REF: legacy computes KSU_VERSION from it (no fixed number in its Makefile)
VERSION=`curl -s -I -k "https://api.github.com/repos/$AUTHOR/$REPO/commits?per_page=1&sha=$REF" | sed -n '/^[Ll]ink:/ s/.*"next".*page=\([0-9]*\).*"last".*/\1/p'`
if [[ -z "$VERSION" ]]; then
	echo "ERROR: Could not get the commit count of $REF from the GitHub API" >&2
	[[ -d drivers/kernelsu ]] && touch drivers/kernelsu/.check
	exit 1
fi

if [[ -f drivers/kernelsu/.version && "$(cat drivers/kernelsu/.version)" == "$VERSION" ]]; then
	touch drivers/kernelsu/.check
	exit 0
fi

# Same formula as legacy's Kbuild uses for a git checkout
KSU_VERSION=$((30000 + VERSION + 289))

# Download first, so a failed download keeps the current drivers/kernelsu
TARBALL=$(mktemp)
trap 'rm -f "$TARBALL"' EXIT
wget -q -O "$TARBALL" "https://github.com/$AUTHOR/$REPO/archive/$REF.tar.gz"

rm -rf drivers/kernelsu
mkdir -p drivers/kernelsu
cd drivers/kernelsu
tar -xzf "$TARBALL" --strip=2 --wildcards --no-wildcards-match-slash "$REPO-*/kernel"
# kernel/include/uapi is a symlink to ../../uapi, outside kernel/: put the real headers there
if [[ -L include/uapi ]]; then
	rm include/uapi
	mkdir include/uapi
	tar -xzf "$TARBALL" -C include/uapi --strip=2 --wildcards --no-wildcards-match-slash "$REPO-*/uapi"
fi

echo "$VERSION" > .version
touch .check

# Apply your kernel-specific Kbuild modifications
# (legacy builds from Kbuild, its Makefile is only used for out-of-tree modules;
# drivers/kernelsu is not a git checkout, so pass the version through the
# override variables Kbuild checks, before it reads them)
sed -i '/warning /d' Kbuild
sed -i "1i KSU_VERSION_OVERRIDE := $KSU_VERSION\nKSU_VERSION_TAG_OVERRIDE := $LATEST_TAG\n" Kbuild

echo "KernelSU-Next $REF KSU_VERSION: $KSU_VERSION"
