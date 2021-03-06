#!/usr/bin/env bash
## Documentation publishing preparation script for Travis CI integration
##
## Copyright (c) 2012-2014 Sylvain Benner
## Copyright (c) 2014-2018 Sylvain Benner & Contributors
##
## Author: Eugene Yaremenko
## URL: https://github.com/syl20bnr/spacemacs
##
## This file is not part of GNU Emacs.
##
## License: GPLv3

fold_start() {
    echo -e "travis_fold:start:$1\033[33;1m$2\033[0m"
}

fold_end() {
    echo -e "\ntravis_fold:end:$1\r"
}

mkdir -p ~/.ssh
printf  "Host  github.com\n" > ~/.ssh/config
printf  "  StrictHostKeyChecking no\n" >> ~/.ssh/config
printf  "  UserKnownHostsFile=/dev/null\n" >> ~/.ssh/config

git config --global user.name "${BOT_NAME}"
git config --global user.email "${BOT_EMAIL}"
git config --global push.default simple
git config --global hub.protocol https
export GITHUB_TOKEN=$BOT_TK

git remote update
base_revision=$(git rev-parse '@')
echo $base_revision > /tmp/base_revision
echo "Base revision $base_revision"

fold_start "UPDATING_BUILT_IN_FILES"
built_in_manifest="${TRAVIS_BUILD_DIR}/.ci/built_in_manifest"
lines=$(cat "${built_in_manifest}")
while read line; do
    url=$(echo $line | cut -f1 -d " ")
    target=$(echo $line | cut -f2 -d " ")
    curl "${url}" --output "${TRAVIS_BUILD_DIR}/${target}"
    if [ $? -ne 0 ]; then
        echo "Failed to update built in file: ${target} from url: ${url}"
        echo "Please update manifest file: .emacs.d/.ci/built_in_manifest"
        exit 2
    fi
done <"${built_in_manifest}"
fold_end "UPDATING_BUILT_IN_FILES"

fold_start "CREATING_BUILT_IN_PATCH_FILE"
git add --all
git commit -m "Built-in files auto-update: $(date -u)"
if [ $? -ne 0 ]; then
    echo "Built-in files don't need an update."
else
    git format-patch -1 HEAD --stdout > /tmp/built_in.patch
    if [ $? -ne 0 ]; then
        echo "Failed to create built-in patch file."
        exit 2
    fi
    git reset --hard HEAD~1
    cat /tmp/built_in.patch
fi
fold_end "CREATING_BUILT_IN_PATCH_FILE"

fold_start "FORMATTING_DOCUMENTATION"
docker run \
       --rm \
       -v "/tmp/elpa/:/root/.emacs.d/elpa/" \
       -v "${TRAVIS_BUILD_DIR}/.ci/spacedoc-cfg.edn":/opt/spacetools/spacedoc-cfg.edn \
       -v "${TRAVIS_BUILD_DIR}":/tmp/docs/ \
       jare/spacetools docfmt /tmp/docs/
if [ $? -ne 0 ]; then
    echo "Formatting failed."
    exit 2
fi
fold_end "FORMATTING_DOCUMENTATION"

fold_start "CREATING_DOCUMENTATION_PATCH_FILE"
git add --all
git commit -m "documentation formatting: $(date -u)"
if [ $? -ne 0 ]; then
    echo "Documentation doesn't need fixes."
else
    git format-patch -1 HEAD --stdout > /tmp/docfmt.patch
    if [ $? -ne 0 ]; then
        echo "Failed to create documentation patch file."
        exit 2
    fi
    git reset --hard HEAD~1
    cat /tmp/docfmt.patch
fi
fold_end "CREATING_DOCUMENTATION_PATCH_FILE"

rm -rf ~/.emacs.d
mv "${TRAVIS_BUILD_DIR}" ~/.emacs.d
cd  ~/.emacs.d
cp ./.travisci/.spacemacs ~/
ln -sf ~/.emacs.d "${TRAVIS_BUILD_DIR}"

fold_start "INSTALLING_DEPENDENCIES"
docker run \
       --rm \
       -v "/tmp/elpa/:/root/.emacs.d/elpa/" \
       -v "${TRAVIS_BUILD_DIR}:/root/.emacs.d" \
       -v "${TRAVIS_BUILD_DIR}/.travisci/.spacemacs:/root/.spacemacs" \
       --entrypoint emacs \
       jare/spacetools -batch -l /root/.emacs.d/init.el
if [ $? -ne 0 ]; then
    echo "Dependencies installation failed."
    exit 2
fi
fold_end "INSTALLING_DEPENDENCIES"

fold_start "EXPORTING_DOCUMENTATION"
docker run \
       --rm \
       -v "/tmp/elpa/:/root/.emacs.d/elpa/" \
       -v "${TRAVIS_BUILD_DIR}:/root/.emacs.d" \
       -v "${TRAVIS_BUILD_DIR}/.travisci/.spacemacs:/root/.spacemacs" \
       --entrypoint emacs \
       jare/spacetools -batch \
       -l /root/.emacs.d/init.el \
       -l /root/.emacs.d/core/core-documentation.el \
       -f spacemacs/publish-doc
if [ $? -ne 0 ]; then
    echo "spacemacs/publish-doc failed"
    exit 2
fi
fold_end "EXPORTING_DOCUMENTATION"

fold_start "INSTALLING_HUB"
hub_version="2.5.1"
hub_url="https://github.com/github/hub/releases/download/"
hub_url+="v${hub_version}/hub-linux-amd64-${hub_version}.tgz"
curl -L $hub_url | tar \
                       --strip-components=2 \
                       -xz \
                       --wildcards \
                       -C /tmp/ \
                       "*hub"
if [ $? -ne 0 ]; then
    echo "Hub installation failed."
    exit 2
fi
fold_end "INSTALLING_HUB"
