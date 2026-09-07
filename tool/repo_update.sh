#!/bin/env bash

REPOS=(
  backing-image-manager
  backupstore
  cli
  csi-attacher
  csi-node-driver-registrar
  csi-provisioner
  csi-resizer
  csi-snapshotter
  dep-versions
  go-common-libs
  go-iscsi-helper
  go-spdk-helper
  longhorn-engine
  longhorn-instance-manager
  longhorn-manager
  longhorn-share-manager
  longhorn-spdk-engine
  longhorn-ui
)
UPSTREAM_BRANCH=upstream

FAILED=()

STASH_DATETIME=$(date "+%Y/%m/%d %H:%M:%S")
for REPO in "${REPOS[@]}"; do
  (
    echo ">>> Updaing ${REPO}"
    #set -x
    set -e

    cd "${REPO}"
    CUR_BRANCH=$(git branch --show-current)
    echo "    Current branch is ${CUR_BRANCH}, checking out to ${UPSTREAM_BRANCH}"
    git clean -df vendor || true
    git restore go.mod go.sum vendor || true
    STASH_LEN_BEFORE=$(git stash list | wc -l)
    git stash -m "repo update ${STASH_DATETIME}" && git sw "${UPSTREAM_BRANCH}"
    git pull --ff-only
    git sw "${CUR_BRANCH}"
    if [[ $STASH_LEN_AFTER -gt $(git stash list | wc -l) ]]; then
      git stash pop
    fi
    for dep_pkg in $(go list -m -mod=mod -f '{{if not (or .Indirect .Main)}}{{.Path}}{{end}}' all | grep 'github.com/longhorn'); do
      dep_repo=$(basename dep_pkg)
      if [[ -d ../$dep_repo ]]; then
        go mod edit -replace "${dep_pkg}=../${dep_repo}"
      fi
    done
  ) || FAILED+=($REPO)
done

if [[ ${#FAILED[@]} -ne 0 ]]; then
  echo
  echo
  echo ">>> Failed repos:"
  for REPO in "${FAILED[@]}"; do
    echo $REPO
  done
  echo
  echo 'Note: execute "go work sync" after fetch to latest changes from upstream.'
else
  go work sync
  echo ">>> All repos updated and work space synced."
fi
