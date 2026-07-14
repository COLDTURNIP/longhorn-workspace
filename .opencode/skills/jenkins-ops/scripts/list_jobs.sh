#!/usr/bin/env bash

DRY_RUN=false
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/jenkins_common.sh"

require_command jq

jq -cS '
  ["regression", "e2e", "benchmark"] as $aliases
  | {
      jobs: [
        $aliases[] as $alias
        | .jobs[$alias] as $job
        | {
            alias: $alias,
            path: ($job.segments | join("/")),
            pipeline: $job.pipeline,
            testSource: $job.testSource,
            runner: $job.runner
          }
      ]
    }
' "$JOBS_FILE"
