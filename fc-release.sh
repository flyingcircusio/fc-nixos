#!/usr/bin/env bash
set -e

releaseid="${1:?no release id given}"

if ! echo "$releaseid" | egrep -q '^[0-9]{4}_[0-9]{3}$'; then
    echo "$0: release id must be of the form YYYY_NNN" >&2
    exit 64
fi

dev="fc-15.09-dev"
stag="fc-15.09-staging"
prod="fc-15.09-production"
echo "$0: performing release based on $stag"

if ! git remote -v | egrep -q "^origin\s.*github.com.flyingcircusio/nixpkgs"
then
    echo "$0: please perform release in a clean checkout with proper origin" >&2
    exit 64
fi
git fetch origin --tags --prune
git checkout $dev
git merge --ff-only  # expected to fail on unclean/unpushed workdirs

git checkout $stag
git merge --ff-only
git tag -a -m "Release r$releaseid" "fc/r$releaseid"

git checkout $prod
git merge --ff-only
msg="Merge branch '$stag' into $prod for release $releaseid"
git merge -m "$msg" $stag

git checkout $dev
msg="Backmerge branch '$prod' into $dev for release $releaseid"
git merge -m "$msg" $prod

echo "$0: committed changes:"
PAGER= git log --graph --decorate --format=short -n3

cmd="git push origin $dev $stag $prod fc/r$releaseid"
echo "$0: If this looks correct, press Enter to push (or use ^C to abort)."
echo "$0: This will issue: $cmd"
read
eval $cmd
