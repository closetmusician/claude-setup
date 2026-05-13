#!/bin/bash

# exit when any command fails
set -e

repo=$1
description=$2
org=$3

echo "Running template repo script"

# Configure git
git config user.name 'diligentgithubadmin'
git config user.email '<diligentgithubadmin@users.noreply.github.com>'

# Install yq
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod a+x /usr/local/bin/yq
yq --version

# Modifying config file to match the repo
yq e -i ".owner = \"\"" .diligent/catalog/diligent-base-template.yaml
yq e -i ".entityTag = \"$repo\"" .diligent/catalog/diligent-base-template.yaml
yq e -i ".primaryParentEntityTag = \"\"" .diligent/catalog/diligent-base-template.yaml
yq e -i ".description = \"$description\"" .diligent/catalog/diligent-base-template.yaml
yq e -i ".github.organization = \"$org\"" .diligent/catalog/diligent-base-template.yaml
yq e -i ".github.repository = \"$repo\"" .diligent/catalog/diligent-base-template.yaml
yq e -i ".dateVerified = \"2024-01-01\"" .diligent/catalog/diligent-base-template.yaml
yq e -i ".opsgenie.opsgenieScheduleId = \"\"" .diligent/catalog/diligent-base-template.yaml
yq e -i ".opsgenie.opsgenieTeamName = \"\"" .diligent/catalog/diligent-base-template.yaml
yq e -i ".msTeamsChannels = []" .diligent/catalog/diligent-base-template.yaml

git mv .diligent/catalog/diligent-base-template.yaml .diligent/catalog/$repo.yaml

# commit changes
git add .diligent/catalog/$repo.yaml
git commit -m "Modified config file to match the repo"

# Push changes to main
git status
git push
