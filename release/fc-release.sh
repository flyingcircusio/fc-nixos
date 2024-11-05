#!/usr/bin/env bash
set -e

releaseid="${1:?no release id given}"

if ! echo "$releaseid" | grep -Eq '^[0-9]{4}_[0-9]{3}$'; then
    echo "$0: release id must be of the form YYYY_NNN" >&2
    exit 64
fi

nixos_version=$(< release/nixos-version)
dev="fc-${nixos_version}-dev"
stag="fc-${nixos_version}-staging"
prod="fc-${nixos_version}-production"

echo "$0: performing release based on $stag"

if ! git remote -v | grep -Eq "^origin\s.*github.com.flyingcircusio/fc-nixos"; then
    echo "$0: please perform release in a clean checkout with proper origin" >&2
    exit 64
fi

if [[ ! -d ../doc/changelog.d ]] || ! git -C ../doc remote -v | grep -Eq "^origin\s.*github.com.flyingcircusio/doc"; then
    echo "$0: please ensure that you have a checkout of flyingcircusio/doc next to this repo"
    exit 64
fi
if [[ -e ../doc/changelog.d/"$nixos_version".md ]]; then
    echo "$0: the changelog fragment '../doc/changelog.d/$nixos_version.md' already exists"
    exit 64
fi

git fetch origin --tags --prune
git checkout "$dev"
git merge --ff-only  # expected to fail on unclean/unpushed workdirs

git checkout "$stag"
git merge --ff-only

TEMP_CHANGELOG=changelog.d/CHANGELOG.md.tmp
CHANGELOG=changelog.d/CHANGELOG.md
truncate -s 0 $TEMP_CHANGELOG
scriv collect --add
sed -e "s/^## Impact/## Impact\n### $nixos_version/" \
    -e "s/^## NixOS XX.XX platform/## NixOS $nixos_version platform/" $TEMP_CHANGELOG > ../doc/changelog.d/"$nixos_version".md
echo -e "\n" >> $TEMP_CHANGELOG
cat $CHANGELOG >> $TEMP_CHANGELOG
(echo "# Release $releaseid"; cat $TEMP_CHANGELOG) > $CHANGELOG
rm $TEMP_CHANGELOG
git add $TEMP_CHANGELOG $CHANGELOG
git commit -m "Collect changelog fragments"

git checkout "$prod"
git merge --ff-only

msg="Merge branch '$stag' into $prod for release $releaseid"
git merge -m "$msg" "$stag"

git checkout "$dev"
msg="Backmerge branch '$prod' into $dev for release $releaseid"
git merge -m "$msg" "$prod"

echo "$0: committed changes:"
PAGER='' git log --graph --decorate --format=short -n3

cmd="git push origin $dev $stag $prod"
echo "$0: If this looks correct, press Enter to push (or use ^C to abort)."
echo "$0: This will issue: $cmd"
read -r
eval "$cmd"
