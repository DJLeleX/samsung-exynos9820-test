#!/bin/bash
set -e -o pipefail
exec 9>.kernelsu-fetch-lock
flock -n 9 || exit 0
[[ $(( $(date +%s) - $(stat -c %Y "drivers/kernelsu/.check" 2>/dev/null || echo 0) )) -gt 86400 ]] || exit 0

AUTHOR="backslashxx"
REPO="KernelSU"

#LATEST COMMIT
#VERSION=`curl -s -I -k "https://api.github.com/repos/$AUTHOR/$REPO/commits?per_page=1" | sed -n '/^[Ll]ink:/ s/.*"next".*page=\([0-9]*\).*"last".*/\1/p'`
#LATEST RELEASE
LATEST_RELEASE=$(curl -s -k "https://api.github.com/repos/$AUTHOR/$REPO/releases/latest" | grep -oP '"tag_name": "\K[^"]+')
#HARDCODED COMMIT
#COMMIT="648e5988cf421172769f80ce07f86331b548c053"
#VERSION=`curl -s -I -k "https://api.github.com/repos/$AUTHOR/$REPO/commits?per_page=1&sha=$COMMIT" | sed -n '/^[Ll]ink:/ s/.*"next".*page=\([0-9]*\).*"last".*/\1/p'`

if [[ -f drivers/kernelsu/.version && *$(cat drivers/kernelsu/.version)* == *$VERSION* ]]; then
	touch drivers/kernelsu/.check
	exit 0
fi

# printf "$REPO updating to $((10000+$VERSION+200))\n"
rm -rf drivers/kernelsu
mkdir -p drivers/kernelsu
cd drivers/kernelsu
#LATEST COMMIT
#wget -q -O - https://github.com/$AUTHOR/$REPO/archive/refs/heads/main.tar.gz | tar -xz --strip=2 "$REPO-main/kernel"
#LATEST RELEASE
wget -q -O - "https://github.com/$AUTHOR/$REPO/archive/refs/tags/$LATEST_RELEASE.tar.gz" | tar -xz --strip=2 --wildcards "$REPO-*/kernel"
#HARDCODED COMMIT
#wget -q -O - "https://github.com/$AUTHOR/$REPO/archive/$COMMIT.tar.gz" | tar -xz --strip=2 "$REPO-$COMMIT/kernel"
#EXTRACT VERSION FROM MAKEFILE
VERSION=$(grep -hE -- '-DKSU_VERSION=[0-9]+' Makefile | grep -oE '[0-9]+' | tail -n1)
if [[ -z "$VERSION" ]]; then
    echo "ERROR: Could not extract KSU_VERSION from KernelSU Makefile" >&2
    exit 1
fi

echo "$VERSION" > .version
touch .check

# Apply your kernel-specific Makefile modifications
sed -i '/warning /d; /DKSU_VERSION/d' Makefile
printf '\nccflags-y += -DKSU_VERSION=%s\n' "$VERSION" >> Makefile

echo "KernelSU KSU_VERSION: $VERSION"
