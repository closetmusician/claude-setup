#!/bin/bash

# exit when any command fails
set -e

repo=$1
description=$2
org=$3

echo "Running template repo script"

# Configure git
git config user.name 'gitadmin'
git config user.email '<gitadmin@users.noreply.github.com>'

# Install yq
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod a+x /usr/local/bin/yq
yq --version

# Modifying config file to match the repo
yq e -i ".owner = \"\"" .acme/catalog/acme-base-template.yaml
yq e -i ".entityTag = \"$repo\"" .acme/catalog/acme-base-template.yaml
yq e -i ".primaryParentEntityTag = \"\"" .acme/catalog/acme-base-template.yaml
yq e -i ".description = \"$description\"" .acme/catalog/acme-base-template.yaml
yq e -i ".github.organization = \"$org\"" .acme/catalog/acme-base-template.yaml
yq e -i ".github.repository = \"$repo\"" .acme/catalog/acme-base-template.yaml
yq e -i ".dateVerified = \"2024-01-01\"" .acme/catalog/acme-base-template.yaml
yq e -i ".opsgenie.opsgenieScheduleId = \"\"" .acme/catalog/acme-base-template.yaml
yq e -i ".opsgenie.opsgenieTeamName = \"\"" .acme/catalog/acme-base-template.yaml
yq e -i ".msTeamsChannels = []" .acme/catalog/acme-base-template.yaml

git mv .acme/catalog/acme-base-template.yaml .acme/catalog/$repo.yaml

# commit changes
git add .acme/catalog/$repo.yaml
git commit -m "Modified config file to match the repo"

# Push changes to main
git status
git push
