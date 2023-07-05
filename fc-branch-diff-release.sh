#! /usr/bin/env nix-shell
#! nix-shell -i bash --pure -p git gh coreutils

nixos_version=$(< nixos-version)
dev="fc-${nixos_version}-dev"
stag="fc-${nixos_version}-staging"
prod="fc-${nixos_version}-production"

export PAGER=

dev_commit=$(git rev-parse $dev)
stag_commit=$(git rev-parse $stag)
prod_commit=$(git rev-parse $prod)

num_dev_prod_commits=$(git cherry "$prod" "$dev" | wc -l)

echo "Comparing $dev to $prod $prod_commit..$dev_commit"
echo "$stag is at $stag_commit"

echo
echo "Merged PRs:"
echo
echo gh pr list --state=merged -B "$dev"
gh pr list --state=merged -B "$dev"
echo
echo "Commits in $dev, not in $stag:"
echo
echo git cherry "$stag" "$dev" -v
git cherry "$stag" "$dev" -v
echo
echo "Commits in $dev, not in $prod ($num_dev_prod_commits):"
echo
echo git cherry "$prod" "$dev" -v
git cherry "$prod" "$dev" -v
echo
echo git diff "$prod" "$dev"
echo "Press Enter to show full diff"

read -r

git diff "$prod" "$dev"
