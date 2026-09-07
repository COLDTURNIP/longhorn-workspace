#!/usr/bin/env bash
# Sourced by the existing loopback-only contract runner.

storage_trigger_contracts() {
    local path mode bad_args
    start_fixture normal || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" storage-network
    assert_status 0 "storage-network default preview" || return 1
    path=$(assert_private_path "storage-network launch plan") || return 1
    assert_private_dir "$(dirname "$path")" || return 1
    assert_json_file "$path" '.job=="storage-network" and .warnings==[] and .execution.runner=="PyTest" and .execution.testType=="pytest" and .execution.testImage=="longhorn-tests:latest" and .execution.customTestOptions=="-m smoke" and all(.parameters[]; .name != "CUSTOM_SSH_PUBLIC_KEY") and any(.parameters[]; .name=="RUN_V2_TEST" and .value==false and .source=="jenkins-default")' "storage-network defaults and no e2e warning" || return 1
    assert_all_get || return 1

    for mode in storage-robot storage-empty storage-missing-type storage-other-type; do
        start_fixture "$mode" || return 4
        run_capture "$SKILL_DIR/scripts/trigger_job.sh" storage-network
        assert_status 0 "storage runner preview $mode" || return 1
        path=$(assert_private_path "storage runner preview $mode") || return 1
        if [ "$mode" = storage-robot ]; then
            assert_json_file "$path" '.execution.runner=="Robot Framework" and .execution.testType=="robot" and .execution.testImage=="longhornio/longhorn-e2e-test:master-head"' "Robot image fallback" || return 1
        else
            assert_json_file "$path" '.execution.runner=="PyTest"' "non-Robot source branch" || return 1
            if [ "$mode" = storage-empty ]; then
                assert_json_file "$path" '.execution.testType=="pytest" and .execution.testImage=="longhornio/longhorn-manager-test:master-head"' "PyTest image and type fallback" || return 1
            fi
        fi
        assert_all_get || return 1
    done

    start_fixture normal || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" storage-network TEST_TYPE=pytest RUN_V2_TEST=true 'CUSTOM_TEST_OPTIONS=-k "expansion or reconnect"'
    assert_status 0 "storage PyTest V2 marker preview" || return 1
    path=$(assert_private_path "storage PyTest V2 marker preview") || return 1
    assert_json_file "$path" '.execution.runner=="PyTest" and (.execution.customTestOptions | endswith(" -m v2_volume_test")) and (.warnings|length)==1 and any(.parameters[]; .name=="CUSTOM_TEST_OPTIONS" and (.value|contains("v2_volume_test")|not))' "pipeline marker is described, not submitted" || return 1
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" storage-network TEST_TYPE=robot RUN_V2_TEST=true 'CUSTOM_TEST_OPTIONS=-t "Storage Network"' LONGHORN_TESTS_CUSTOM_IMAGE=fixture/robot:custom
    assert_status 0 "storage Robot V2 marker preview" || return 1
    path=$(assert_private_path "storage Robot V2 marker preview") || return 1
    assert_json_file "$path" '.execution.runner=="Robot Framework" and .execution.testImage=="fixture/robot:custom" and (.execution.customTestOptions|endswith(" -m v2_volume_test")) and (.warnings|length)==1' "Robot does not bypass pipeline marker mutation" || return 1
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" storage-network RUN_V2_TEST=true 'CUSTOM_TEST_OPTIONS=-m coretest'
    assert_status 0 "storage existing marker preview" || return 1
    path=$(assert_private_path "storage existing marker preview") || return 1
    assert_json_file "$path" '.execution.customTestOptions=="-m coretest" and .warnings==[]' "existing marker preserved" || return 1
    assert_all_get || return 1

    for bad_args in TEST_TYPE=unknown RUN_V2_TEST=FALSE UNKNOWN=value; do
        run_capture "$SKILL_DIR/scripts/trigger_job.sh" --execute storage-network "$bad_args"
        assert_status 2 "storage invalid live parameter" || return 1
    done
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" --execute storage-network TEST_TYPE=pytest TEST_TYPE=robot
    assert_status 2 "storage duplicate override" || return 1
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" --execute storage-network 'CUSTOM_TEST_OPTIONS=-k $(unsupported)'
    assert_status 2 "storage unsafe options" || return 1
    assert_no_post || return 1
    for mode in duplicate-conflict malformed-definitions; do
        start_fixture "$mode" || return 4
        run_capture "$SKILL_DIR/scripts/trigger_job.sh" --execute storage-network
        assert_status 4 "storage invalid metadata $mode" || return 1
        assert_no_post || return 1
    done
    start_fixture raw-types || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" --execute storage-network
    assert_status 2 "storage unsupported live types" || return 1
    assert_no_post || return 1

    # The source generates its own node key. A live missing key parameter must
    # ignore even an unavailable fallback file, rather than inventing support.
    start_fixture post-201 || return 4
    export JENKINS_NOTIFY_SLACK_CHANNEL=fixture-channel
    run_capture_env JENKINS_SSH_PUBLIC_KEY="$RUN_DIR/missing-storage-key" "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" --execute storage-network TEST_TYPE=robot RUN_V2_TEST=false 'CUSTOM_TEST_OPTIONS=-t "Storage Network"'
    assert_status 0 "storage trigger-and-forget" || return 1
    assert_json_stdout '.job=="storage-network" and .queueId==101 and .state=="QUEUED" and (keys==["job","queueId","state"])' "storage enqueue result" || return 1
    assert_log '([.[] | select(.method=="POST")]|length)==1 and all(.[] | select(.method=="POST"); .path=="/job/private/job/longhorn-storage-network-test/buildWithParameters" and .crumb=="ok" and any(.form[]; .name=="TEST_TYPE" and .value=="robot") and any(.form[]; .name=="RUN_V2_TEST" and .value=="false") and any(.form[]; .name=="SEND_SLACK_NOTIFICATION" and .value=="true") and any(.form[]; .name=="NOTIFY_SLACK_CHANNEL" and .value=="fixture-channel") and all(.form[]; .name!="CUSTOM_SSH_PUBLIC_KEY")) and all(.[]; (.path|contains("/queue/") or contains("/consoleText") or contains("/7/"))|not)' "storage exact POST and no follow-on" || return 1
    assert_output_absent fixture-channel "storage managed channel output" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "storage key output" || return 1
    assert_output_absent "$JENKINS_URL" "storage URL output" || return 1
    start_fixture post-status-500 || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" --execute storage-network
    assert_status 4 "storage failed POST" || return 1
    assert_log '([.[] | select(.method=="POST")]|length)==1' "storage POST not retried" || return 1
    return 0
}

storage_monitor_contracts() {
    local mode
    start_fixture storage-expired || return 4
    run_capture "$SKILL_DIR/scripts/get_build_status.sh" storage-network 7
    assert_status 0 "storage build status" || return 1
    assert_json_stdout '.job=="storage-network" and .build==7 and .queueId==101' "storage status identity" || return 1
    run_capture "$SKILL_DIR/scripts/list_builds.sh" storage-network 2
    assert_status 0 "storage recent builds" || return 1
    assert_json_stdout '.job=="storage-network" and [.builds[].build]==[7,6]' "storage recent builds identity" || return 1
    run_capture "$SKILL_DIR/scripts/resolve_build.sh" storage-network 101 2
    assert_status 0 "storage queue correlation" || return 1
    assert_json_stdout '.job=="storage-network" and .queueId==101 and .build==7' "storage resolved identity" || return 1
    run_capture "$SKILL_DIR/scripts/resolve_build.sh" storage-network 999 2
    assert_status 5 "storage missing correlation" || return 1
    for mode in storage-queue storage-expired; do
        start_fixture "$mode" || return 4
        run_capture "$SKILL_DIR/scripts/wait_for_build.sh" 101 20
        assert_status 0 "storage queue wait $mode" || return 1
        assert_json_stdout '.job=="storage-network" and .queueId==101 and .build==7 and .result=="SUCCESS"' "storage wait result" || return 1
        assert_all_get || return 1
        assert_log 'all(.[]; (.path|contains("pull-request-check"))|not)' "storage wait target bound" || return 1
        if [ "$mode" = storage-expired ]; then
            assert_log '([.[]|select(.query|contains("tree=builds[number,queueId,building,result]{0,100}"))]|length)==4 and ([.[]|select(.path|test("/[0-9]+/api/json$"))|select(.path|contains("/job/"))]|length)==1' "four bounded jobs and one correlated build" || return 1
        fi
    done
    for mode in storage-ambiguous queue-forbidden; do
        start_fixture "$mode" || return 4
        run_capture "$SKILL_DIR/scripts/wait_for_build.sh" 101 20
        assert_status 4 "queue refusal $mode" || return 1
        assert_log 'all(.[]; (.path|contains("pull-request-check"))|not) and all(.[]; (.path|test("/job/.*/[0-9]+/api/json$"))|not)' "refused queue never contacts a build" || return 1
    done
    return 0
}

storage_inspect_contracts() {
    local mode manifest path key rel
    for mode in storage-pytest-report storage-robot-report; do
        start_fixture "$mode" || return 4
        run_capture "$SKILL_DIR/scripts/inspect_build.sh" storage-network 7
        assert_status 0 "storage inspection $mode" || return 1
        manifest=$(assert_private_path "storage inspection $mode") || return 1
        assert_private_dir "$(dirname "$manifest")" || return 1
        assert_json_file "$manifest" '.job=="storage-network" and .build==7' "storage inspection identity" || return 1
        if [ "$mode" = storage-pytest-report ]; then
            assert_json_file "$manifest" '.files.junit=="test-report.json" and .files.robot==null' "storage PyTest report" || return 1
            assert_log 'all(.[]; (.path|endswith("/robot/api/json"))|not)' "no guessed Robot endpoint" || return 1
        else
            assert_json_file "$manifest" '.files.junit==null and .files.robot=="robot-report.json"' "storage Robot report" || return 1
            assert_log 'any(.[]; .path|endswith("/robot/api/json"))' "Robot action report endpoint" || return 1
        fi
        for key in build console artifacts remoteHosts junit robot; do
            rel=$(jq -r ".files.$key" "$manifest")
            [ "$rel" != null ] || continue
            path="$(dirname "$manifest")/$rel"
            python -c 'import os,stat,sys; sys.exit(stat.S_IMODE(os.stat(sys.argv[1]).st_mode) != 0o600)' "$path" || return 1
        done
        assert_json_file "$(dirname "$manifest")/artifacts.json" '.artifacts==[{fileName:"fixture-bundle.zip",relativePath:"fixture-bundle.zip"}]' "storage support bundle catalog" || return 1
        run_capture "$SKILL_DIR/scripts/get_artifact.sh" storage-network 7 fixture-bundle.zip
        assert_status 0 "storage selected artifact" || return 1
        path=$(assert_private_path "storage artifact") || return 1
        run_capture "$SKILL_DIR/scripts/get_artifact.sh" storage-network 7 output.xml
        assert_status 2 "Robot report is not a guessed archived artifact" || return 1
        assert_all_get || return 1
    done
    start_fixture host-wait-ready || return 4
    : > "$FAKE_SSH_LOG"
    run_capture "$SKILL_DIR/scripts/wait_for_job_host.sh" storage-network 7 60
    assert_status 0 "storage host wait" || return 1
    path=$(assert_private_path "storage host wait") || return 1
    assert_json_file "$path" '.job=="storage-network" and .result=="READY"' "storage host ready" || return 1
    [ ! -s "$FAKE_SSH_LOG" ] || { fail "storage host wait invoked SSH"; return 1; }
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" --resolve-only storage-network 7
    assert_status 0 "storage host resolve-only" || return 1
    path=$(assert_private_path "storage host target") || return 1
    assert_json_file "$path" '.job=="storage-network" and .build==7' "storage SSH identity" || return 1
    [ ! -s "$FAKE_SSH_LOG" ] || { fail "storage resolve-only invoked SSH"; return 1; }
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" storage-network 7 -- true
    assert_status 0 "storage fixture-only SSH" || return 1
    [ -s "$FAKE_SSH_LOG" ] || { fail "storage fixture SSH not invoked"; return 1; }
    assert_output_absent "$RESOLVED_IDENTITY_FILE" "storage identity output" || return 1
    assert_output_absent "$JENKINS_URL" "storage host URL output" || return 1
    assert_all_get || return 1
    return 0
}
