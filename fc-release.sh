#!/usr/bin/env bash
set -e

nixos_version="22.05"
releaseid="${1:?no release id given}"

if ! echo "$releaseid" | grep -Eq '^[0-9]{4}_[0-9]{3}$'; then
    echo "$0: release id must be of the form YYYY_NNN" >&2
    exit 64
fi

dev="fc-${nixos_version}-dev"
stag="fc-${nixos_version}-staging"
prod="fc-${nixos_version}-production"
echo "$0: performing release based on $stag"

if ! git remote -v | grep -Eq "^origin\s.*github.com.flyingcircusio/fc-nixos"
then
    echo "$0: please perform release in a clean checkout with proper origin" >&2
    exit 64
fi
git fetch origin --tags --prune
git checkout $dev
git merge --ff-only  # expected to fail on unclean/unpushed workdirs

git checkout $stag
git merge --ff-only

git checkout $prod
git merge --ff-only
msg="Merge branch '$stag' into $prod for release $releaseid"
git merge -m "$msg" $stag

git checkout $dev
msg="Backmerge branch '$prod' into $dev for release $releaseid"
git merge -m "$msg" $prod

echo "$0: committed changes:"
PAGER='' git log --graph --decorate --format=short -n3

cmd="git push origin $dev $stag $prod"
echo "$0: If this looks correct, press Enter to push (or use ^C to abort)."
echo "$0: This will issue: $cmd"
read -r
eval "$cmd"
