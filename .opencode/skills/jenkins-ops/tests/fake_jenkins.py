#!/usr/bin/env python
"""Deterministic, loopback-only Jenkins HTTP fixture for the jenkins-ops tests."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qsl, unquote, urlsplit


CATALOG = {
    "regression": {
        "name": "longhorn-tests-regression",
        "pipeline": "repo/longhorn-tests/test_framework/Jenkinsfile",
        "testSource": "external image: LONGHORN_TESTS_CUSTOM_IMAGE",
        "runner": "PyTest",
    },
    "e2e": {
        "name": "longhorn-e2e-test",
        "pipeline": "repo/longhorn-tests/pipelines/e2e/Jenkinsfile",
        "testSource": "external image: LONGHORN_TESTS_CUSTOM_IMAGE",
        "runner": "Robot Framework",
    },
    "benchmark": {
        "name": "longhorn-benchmark-test",
        "pipeline": "repo/longhorn-tests/benchmark_test/Jenkinsfile",
        "testSource": "checkout: benchmark_test scripts and manifests",
        "runner": "kbench",
    },
}

# The runner has used both spellings while the fixture was being developed. They
# intentionally map to the same deterministic behavior and keep old scenarios
# useful without changing the public server protocol.
SCENARIO_ALIASES = {
    "auth401": "http-401",
    "forbid403": "http-403-read",
    "notfound404": "http-404",
    "transient500-once": "get-retry-once",
    "crumb-missing": "crumb-missing",
    "crumb-malformed": "crumb-malformed",
    "trigger201": "post-201",
    "trigger302": "post-302",
    "bad-location": "post-location-foreign",
    "trigger-status": "post-status-400",
    "queue-cancel": "queue-cancel-before",
    "timeout-pre": "queue-timeout-before",
    "timeout-post": "queue-timeout-after",
    "reports": "reports-artifacts",
    "artifacts": "reports-artifacts",
    "ip-zero": "console-no-ip",
    "ip-multiple": "console-multiple-ip",
    "queue-pending": "queue-build-transition",
    "queue-pending-multi": "queue-pending-multi",
    "ssh": "normal",
}

SCENARIOS = {
    "normal",
    "raw-types",
    "required-space",
    "duplicate-identical",
    "duplicate-conflict",
    "ssh-key-missing",
    "malformed-definitions",
    "buildable-false",
    "e2e-false-explicit",
    "e2e-false-omitted",
    "e2e-false-default",
    "crumb-disabled",
    "crumb-malformed",
    "crumb-missing",
    "post-201",
    "post-302",
    "post-status-400",
    "post-status-403",
    "post-location-missing",
    "post-status-500",
    "post-location-foreign",
    "get-retry-once",
    "get-retry-exhausted",
    "queue-cancel-before",
    "queue-timeout-before",
    "queue-timeout-after",
    "queue-pending-multi",
    "queue-build-transition",
    "queue-expired-recover",
    "queue-expired-not-found",
    "build-failure",
    "reports-artifacts",
    "reports-missing",
    "console-no-ip",
    "console-multiple-ip",
    "console-ipv6",
    "console-ipv6-compressed",
    "console-invalid-ipv6",
    "console-unbracketed-ipv6",
    "console-mixed-ip",
    "wait-hang",
    "host-wait-ready",
    "host-wait-multiple",
    "host-wait-ipv6-ready",
    "host-wait-timeout",
    "http-401",
    "http-403-read",
    "http-403-build",
    "http-404",
    "http-500",
}

AUTH_USER = "dummy-user"
AUTH_TOKEN = "dummy-token"
CRUMB_FIELD = "Jenkins-Crumb"
CRUMB_VALUE = "dummy-crumb"

JOB_PATH_RE = re.compile(r"^/job/private/job/([^/]+)(?:/(.*))?$")
QUEUE_PATH_RE = re.compile(r"^/queue/item/([1-9][0-9]*)/api/json$")
BUILD_PATH_RE = re.compile(r"^/job/private/job/([^/]+)/([1-9][0-9]*)/(.*)$")
SENSITIVE_NAME_RE = re.compile(r"(?:TOKEN|PASSWORD|SECRET|CREDENTIAL|PRIVATE_KEY)", re.I)


def _json_bytes(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def _base_job_path(job_name):
    return "/job/private/job/{}".format(job_name)


def _definitions(alias, mode):
    """Return Jenkins-shaped parameter definitions for one catalog alias."""
    common = [
        {
            "name": "CUSTOM_TEST_OPTIONS",
            "type": "TextParameterDefinition",
            "description": "Additional test options",
            "defaultParameterValue": {"value": "-m smoke"},
        },
        {
            "name": "LONGHORN_REPO_BRANCH",
            "type": "ChoiceParameterDefinition",
            "description": "Checkout branch",
            "defaultParameterValue": {"value": "main"},
            "choices": ["main", "master", "v1.7.x"],
        },
        {
            "name": "LONGHORN_REPO_URI",
            "type": "StringParameterDefinition",
            "description": "Checkout URI",
            "defaultParameterValue": {
                "value": "https://github.com/longhorn/longhorn-tests.git"
            },
        },
        {
            "name": "LONGHORN_TESTS_CUSTOM_IMAGE",
            "type": "StringParameterDefinition",
            "description": "External test image",
            "defaultParameterValue": {"value": "longhorn-tests:latest"},
        },
        {
            "name": "NOTIFY_SLACK_CHANNEL",
            "type": "StringParameterDefinition",
            "description": "Slack channel ID for job notifications",
            "defaultParameterValue": {"value": ""},
        },
        {
            "name": "SEND_SLACK_NOTIFICATION",
            "type": "BooleanParameterDefinition",
            "description": "Send Slack notification",
            "defaultParameterValue": {"value": True},
        },
    ]
    if alias in {"regression", "e2e"} and not (
        alias == "regression" and mode == "ssh-key-missing"
    ):
        common.append(
            {
                "name": "CUSTOM_SSH_PUBLIC_KEY",
                "type": "StringParameterDefinition",
                "description": "SSH public key for test nodes",
                "defaultParameterValue": {"value": ""},
            }
        )
    if alias == "e2e":
        default = True
        if mode in {"e2e-false-explicit", "e2e-false-omitted", "e2e-false-default"}:
            default = False
        e2e_bool = {
            "name": "RUN_V2_TEST",
            "type": "BooleanParameterDefinition",
            "description": "Run v2 tests",
            "defaultParameterValue": {"value": default},
        }
        common.append(e2e_bool)
    if alias == "benchmark":
        common.extend(
            [
                {
                    "name": "TEST_SIZE",
                    "type": "ChoiceParameterDefinition",
                    "description": "Benchmark size",
                    "defaultParameterValue": {"value": "small"},
                    "choices": ["small", "large"],
                },
                {
                    "name": "LONGHORN_PREVIOUS_VERSION",
                    "type": "StringParameterDefinition",
                    "description": "Previous Longhorn version",
                    "defaultParameterValue": {"value": "v1.6.0"},
                },
                {
                    "name": "CUSTOM_LONGHORN_MANAGER_IMAGE",
                    "type": "StringParameterDefinition",
                    "description": "Manager image",
                    "defaultParameterValue": {"value": "longhorn-manager:latest"},
                },
                {
                    "name": "CUSTOM_LONGHORN_ENGINE_IMAGE",
                    "type": "StringParameterDefinition",
                    "description": "Engine image",
                    "defaultParameterValue": {"value": "longhorn-engine:latest"},
                },
                {
                    "name": "CUSTOM_LONGHORN_INSTANCE_MANAGER_IMAGE",
                    "type": "StringParameterDefinition",
                    "description": "Instance manager image",
                    "defaultParameterValue": {"value": "longhorn-instance-manager:latest"},
                },
                {
                    "name": "CUSTOM_LONGHORN_SHARE_MANAGER_IMAGE",
                    "type": "StringParameterDefinition",
                    "description": "Share manager image",
                    "defaultParameterValue": {"value": "longhorn-share-manager:latest"},
                },
                {
                    "name": "CUSTOM_LONGHORN_BACKING_IMAGE_MANAGER_IMAGE",
                    "type": "StringParameterDefinition",
                    "description": "Backing image manager image",
                    "defaultParameterValue": {"value": "longhorn-backing-image-manager:latest"},
                },
            ]
        )
    if mode == "required-space":
        common.append(
            {
                "name": "REQUIRED TEXT",
                "type": "StringParameterDefinition",
                "description": "Required parameter with whitespace",
            }
        )
    if mode == "raw-types":
        common.extend(
            [
                {
                    "name": "RAW_BOOLEAN",
                    "type": "BooleanParameterDefinition",
                    "description": "Raw boolean parameter",
                    "defaultParameterValue": {"value": True},
                },
                {
                    "name": "RAW_PASSWORD",
                    "type": "PasswordParameterDefinition",
                    "description": "Raw password parameter",
                    "defaultParameterValue": {"value": "fixture-password-value"},
                },
                {
                    "name": "FIXTURE_TOKEN",
                    "type": "PasswordParameterDefinition",
                    "description": "Sensitive fixture parameter",
                    "defaultParameterValue": {"value": "fixture-token-value"},
                },
                {
                    "name": "REQUIRED_TEXT",
                    "type": "StringParameterDefinition",
                    "description": "Required fixture parameter",
                },
            ]
        )
    if mode == "raw-types":
        common.append(
            {
                "name": "UNSUPPORTED_RAW",
                "type": "RunParameterDefinition",
                "description": "An unsupported raw Jenkins type",
                "defaultParameterValue": {"value": "raw-default"},
                "choices": ["raw-default", "other"],
            }
        )
    if mode == "malformed-definitions":
        common.append(
            {
                "name": 17,
                "type": "StringParameterDefinition",
                "description": "malformed name",
            }
        )
    return common


def _job_metadata(alias, mode, buildable=True):
    defs = _definitions(alias, mode)
    if mode == "duplicate-identical":
        defs = defs + [dict(defs[0])]
    elif mode == "duplicate-conflict":
        conflict = dict(defs[0])
        conflict["description"] = "different description"
        defs = defs + [conflict]
    # Splitting definitions across both Jenkins locations exercises the merge
    # and duplicate comparison code in get_job_parameters.sh.
    midpoint = max(1, len(defs) // 2)
    first = defs[:midpoint]
    second = defs[midpoint:]
    return {
        "actions": [{"parameterDefinitions": first}],
        "buildable": buildable,
        "property": [{"parameterDefinitions": second}],
    }


def _console(mode):
    lines = [
        "Provisioning started",
        'controlplane_public_ip = "(known after apply)"',
        'controlplane_public_ip = "-> null"',
        'controlplane_public_ip = "[not-an-ip]"',
        '\x1b[32mcontrolplane_public_ip = "198.51.100.9"\x1b[0m',
    ]
    if mode == "console-no-ip":
        return "\n".join(lines) + "\nProvisioning complete\n"
    if mode == "console-ipv6":
        lines.extend(
            [
                'controlplane_public_ip = "[2600:1f18:671d:ea00:8589:9089:1065:aff9]"',
                'controlplane_public_ip = "[2600:1F18:671D:EA00:8589:9089:1065:AFF9]"',
            ]
        )
        return "\n".join(lines) + "\nProvisioning complete\n"
    if mode == "console-ipv6-compressed":
        lines.append('controlplane_public_ip = "[2001:0db8:0000:0000:0000:0000:0000:0001]"')
        return "\n".join(lines) + "\nProvisioning complete\n"
    if mode == "console-invalid-ipv6":
        lines.append('controlplane_public_ip = "[2001:db8::zzzz]"')
        return "\n".join(lines) + "\nProvisioning complete\n"
    if mode == "console-unbracketed-ipv6":
        lines.append('controlplane_public_ip = "2001:db8::1"')
        return "\n".join(lines) + "\nProvisioning complete\n"
    if mode == "console-mixed-ip":
        lines.extend(
            [
                'controlplane_public_ip = "192.0.2.10"',
                'controlplane_public_ip = "[2001:db8::1]"',
            ]
        )
        return "\n".join(lines) + "\nProvisioning complete\n"
    if mode == "console-multiple-ip":
        lines.extend(
            [
                'controlplane_public_ip = "192.0.2.10"',
                'controlplane_public_ip = "192.0.2.11"',
            ]
        )
    else:
        lines.append('controlplane_public_ip = "192.0.2.10"')
    return "\n".join(lines) + "\nProvisioning complete\n"


class FixtureState:
    def __init__(self, scenario, request_log):
        self.scenario = scenario
        self.request_log = request_log
        self.lock = threading.Lock()
        self.counts = {}
        self.queue_count = 0
        self.build_count = 0
        self.last_form = []
        self.stopping = False

    def count(self, key):
        with self.lock:
            self.counts[key] = self.counts.get(key, 0) + 1
            return self.counts[key]

    def record(self, record):
        if self.request_log is None:
            return
        line = json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n"
        with self.lock:
            self.request_log.write(line)
            self.request_log.flush()


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(self, address, handler, state):
        super().__init__(address, handler)
        self.state = state


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    server_version = "FakeJenkins/1.0"
    sys_version = ""

    def log_message(self, fmt, *args):
        # Do not leak URLs, credentials, or parameter values to stderr.
        return

    @property
    def state(self):
        return self.server.state

    def _auth_outcome(self):
        value = self.headers.get("Authorization")
        if value is None:
            return "missing"
        expected = "Basic " + base64.b64encode(
            (AUTH_USER + ":" + AUTH_TOKEN).encode("ascii")
        ).decode("ascii")
        return "ok" if value == expected else "bad"

    def _crumb_outcome(self, required=True):
        if not required:
            return "not-required"
        value = self.headers.get(CRUMB_FIELD)
        if value is None:
            return "missing"
        return "ok" if value == CRUMB_VALUE else "bad"

    def _parse_form(self, body):
        if not body:
            return []
        return [
            {"name": name, "value": value}
            for name, value in parse_qsl(
                body.decode("utf-8", "replace"),
                keep_blank_values=True,
                strict_parsing=False,
            )
        ]

    def _record(self, method, split, auth, crumb, form, status, body):
        # The body is retained for the runner's method/form assertions. It is
        # never an Authorization header and sensitive form values are redacted.
        safe_form = []
        for item in form:
            value = item["value"]
            if SENSITIVE_NAME_RE.search(item["name"]):
                value = "[REDACTED]"
            safe_form.append({"name": item["name"], "value": value})
        safe_body = ""
        if safe_form:
            encoded = []
            from urllib.parse import quote_plus

            encoded = [
                quote_plus(item["name"], safe="")
                + "="
                + quote_plus(item["value"], safe="")
                for item in safe_form
            ]
            safe_body = "&".join(encoded)
        record = {
            "auth": auth,
            "crumb": crumb,
            "form": safe_form,
            "method": method,
            "path": split.path,
            "query": split.query,
            "status": status,
            "body": safe_body,
        }
        self.state.record(record)

    def _send(self, status, body=b"", headers=None, auth="ok", crumb="not-required", form=None, split=None, method="GET"):
        if headers is None:
            headers = {}
        if form is None:
            form = []
        if split is None:
            split = urlsplit(self.path)
        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        if body:
            self.wfile.write(body)
        self._record(method, split, auth, crumb, form, status, body)

    def _json(self, value, status=200, **kwargs):
        self._send(
            status,
            _json_bytes(value),
            {"Content-Type": "application/json"},
            **kwargs
        )

    def _auth_gate(self, split, method, form):
        outcome = self._auth_outcome()
        scenario = self.state.scenario
        if scenario == "http-401" or outcome != "ok":
            self._send(
                401,
                b"Unauthorized\n",
                {"WWW-Authenticate": 'Basic realm="fake-jenkins"'},
                auth=outcome,
                crumb=(
                    "not-required"
                    if method == "GET"
                    else self._crumb_outcome(scenario != "crumb-disabled")
                ),
                form=form,
                split=split,
                method=method,
            )
            return False
        return True
    def _job_alias(self, name):
        for alias, data in CATALOG.items():
            if data["name"] == name:
                return alias
        return None

    def _job_get(self, split, path):
        match = JOB_PATH_RE.match(path)
        if not match or match.group(2) != "api/json":
            return False
        name = unquote(match.group(1))
        alias = self._job_alias(name)
        scenario = self.state.scenario
        if scenario in {"http-404", "notfound404"} or alias is None:
            self._json({}, status=404, split=split)
            return True
        if scenario == "http-403-read":
            self._json({}, status=403, split=split)
            return True
        if scenario in {"http-500", "get-retry-exhausted"}:
            self._json({}, status=500, split=split)
            return True
        if scenario == "get-retry-once":
            count = self.state.count(("job", name))
            if count == 1:
                self._json({}, status=500, split=split)
                return True
        if split.query.startswith("tree=builds["):
            builds = []
            if alias == "regression" and scenario != "queue-expired-not-found":
                builds = [
                    {
                        "building": False,
                        "number": 7,
                        "queueId": 101,
                        "result": "SUCCESS",
                    },
                    {
                        "building": False,
                        "number": 6,
                        "queueId": 100,
                        "result": "FAILURE",
                    },
                ]
            self._json({"builds": builds}, split=split)
            return True
        buildable = scenario != "buildable-false"
        self._json(
            _job_metadata(alias, scenario, buildable=buildable),
            split=split,
        )
        return True

    def _queue_get(self, split, path):
        match = QUEUE_PATH_RE.match(path)
        if not match:
            return False
        queue_id = int(match.group(1))
        if queue_id != 101:
            self._json({}, status=404, split=split)
            return True
        scenario = self.state.scenario
        if scenario == "http-500":
            self._json({}, status=500, split=split)
            return True
        if scenario in {"http-404", "notfound404"}:
            self._json({}, status=404, split=split)
            return True
        if scenario in {"queue-expired-recover", "queue-expired-not-found"}:
            self._json({}, status=404, split=split)
            return True
        if scenario == "wait-hang":
            self._record("GET", split, "ok", "not-required", [], 0, b"")
            time.sleep(120)
            return True
        if scenario == "queue-cancel-before":
            self._json({"cancelled": True}, split=split)
            return True
        if scenario == "queue-timeout-before":
            self._json({"blocked": False, "cancelled": False, "executable": None}, split=split)
            return True
        if scenario == "queue-pending-multi":
            count = self.state.count("queue")
            if count <= 3:
                self._json(
                    {"blocked": False, "cancelled": False, "executable": None, "why": "pending"},
                    split=split,
                )
                return True
        if scenario == "queue-build-transition":
            count = self.state.count("queue")
            if count == 1:
                self._json(
                    {"blocked": False, "cancelled": False, "executable": None, "why": "pending"},
                    split=split,
                )
                return True
        # queue-timeout-after resolves once and leaves build in progress.
        self._json(
            {
                "blocked": False,
                "cancelled": False,
                "executable": {
                    "number": 7,
                    "url": self._build_url("longhorn-tests-regression", 7),
                },
            },
            split=split,
        )
        return True

    def _origin(self):
        host = self.headers.get("Host", "")
        if host.startswith("127.0.0.1:") or host.startswith("localhost:"):
            return "http://" + host
        return "http://127.0.0.1:{}".format(self.server.server_port)
    def _build_url(self, name, number):
        return "{}/job/private/job/{}/{}/".format(
            self._origin(), name, number
        )

    def _build_get(self, split, path):
        match = BUILD_PATH_RE.match(path)
        if not match:
            return False
        name, number_text, suffix = match.groups()
        alias = self._job_alias(unquote(name))
        number = int(number_text)
        scenario = self.state.scenario
        if scenario == "http-500":
            self._json({}, status=500, split=split)
            return True
        if alias is None or number != 7:
            self._json({}, status=404, split=split)
            return True
        if suffix == "api/json":
            if scenario == "http-404":
                self._json({}, status=404, split=split)
                return True
            if scenario == "http-403-read":
                self._json({}, status=403, split=split)
                return True
            count = self.state.count(("build", name, number))
            if scenario in {"queue-timeout-after", "timeout-post"}:
                building, result = True, None
            elif scenario == "build-failure":
                building, result = False, "FAILURE"
            elif count == 1 and scenario in {"queue-build-transition", "queue-pending"}:
                building, result = True, None
            else:
                building, result = False, "SUCCESS"
            actions = [
                {
                    "_class": "hudson.model.ParametersAction",
                    "parameters": [
                        {"name": item["name"], "value": item["value"]}
                        for item in sorted(self.state.last_form, key=lambda item: item["name"])
                    ],
                }
            ]
            if scenario in {"reports-artifacts", "reports", "artifacts"}:
                actions.append(
                    {
                        "_class": "hudson.plugins.robot.RobotBuildAction",
                        "urlName": "robot",
                        "parameters": [],
                    }
                )
            artifacts = []
            if scenario in {"reports-artifacts", "reports", "artifacts"}:
                artifacts = [
                    {"fileName": "test-report.json", "relativePath": "reports/test-report.json"},
                    {"fileName": "console.txt", "relativePath": "logs/console.txt"},
                    {"fileName": "results.xml", "relativePath": "artifacts/results.xml"},
                ]
            self._json(
                {
                    "actions": actions,
                    "artifacts": artifacts,
                    "building": building,
                    "queueId": 101,
                    "number": number,
                    "result": result,
                },
                split=split,
            )
            return True
        if suffix == "consoleText":
            if scenario == "host-wait-timeout":
                self._record("GET", split, "ok", "not-required", [], 0, b"")
                time.sleep(120)
                return True
            if scenario == "host-wait-ready":
                console_count = self.state.count(("console", name, number))
                mode = "console-no-ip" if console_count <= 2 else "reports-artifacts"
            elif scenario == "host-wait-ipv6-ready":
                console_count = self.state.count(("console", name, number))
                mode = "console-no-ip" if console_count <= 2 else "console-ipv6"
            elif scenario == "host-wait-multiple":
                mode = "console-multiple-ip"
            else:
                mode = scenario
            if mode in {"reports", "artifacts"}:
                mode = "reports-artifacts"
            body = _console(mode).encode("utf-8")
            self._send(200, body, {"Content-Type": "text/plain; charset=utf-8"}, split=split)
            return True
        if suffix == "testReport/api/json":
            if scenario in {"reports-missing"}:
                self._json({}, status=404, split=split)
            else:
                self._json(
                    {"failCount": 0, "skipCount": 0, "passCount": 1, "suites": [{"name": "fake", "cases": 1}]},
                    split=split,
                )
            return True
        if suffix == "robot/api/json":
            if scenario in {"reports-missing"}:
                self._json({}, status=404, split=split)
            elif scenario in {"reports-artifacts", "reports", "artifacts"}:
                self._json({"statistics": {"total": 1, "passed": 1, "failed": 0}, "generated": True}, split=split)
            else:
                self._json({}, status=404, split=split)
            return True
        if suffix == "api/json":
            return True
        if suffix.startswith("artifact/"):
            relative = unquote(suffix[len("artifact/") :])
            allowed = {"reports/test-report.json", "logs/console.txt", "artifacts/results.xml"}
            if relative not in allowed:
                self._send(404, b"Not found\n", split=split)
            elif relative == "reports/test-report.json":
                self._send(200, _json_bytes({"fake": True, "result": "SUCCESS"}), {"Content-Type": "application/json"}, split=split)
            elif relative == "artifacts/results.xml":
                self._send(200, b"<results><result>SUCCESS</result></results>\n", {"Content-Type": "application/xml"}, split=split)
            else:
                self._send(200, _console(scenario).encode("utf-8"), {"Content-Type": "text/plain"}, split=split)
            return True
        return False

    def _crumb_get(self, split):
        scenario = self.state.scenario
        if scenario == "http-500":
            self._json({}, status=500, split=split)
            return
        if scenario == "crumb-disabled":
            self._json({}, status=404, split=split)
        elif scenario in {"crumb-malformed", "crumb-missing"}:
            self._json({"crumb": "", "crumbRequestField": ""}, split=split)
        else:
            self._json({"crumb": CRUMB_VALUE, "crumbRequestField": CRUMB_FIELD}, split=split)

    def _trigger_post(self, split, form):
        auth = self._auth_outcome()
        crumb_required = self.state.scenario != "crumb-disabled"
        crumb = self._crumb_outcome(crumb_required)
        if auth != "ok":
            self._send(401, b"Unauthorized\n", auth=auth, crumb=crumb, form=form, split=split, method="POST")
            return
        if crumb not in {"ok", "not-required"}:
            self._send(403, b"Forbidden\n", auth=auth, crumb=crumb, form=form, split=split, method="POST")
            return
        scenario = self.state.scenario
        if scenario in {"http-403-build", "post-status-403"}:
            self._send(403, b"Forbidden\n", auth=auth, crumb=crumb, form=form, split=split, method="POST")
            return
        if scenario in {"post-status-400", "trigger-status"}:
            self._send(400, b"Bad request\n", auth=auth, crumb=crumb, form=form, split=split, method="POST")
            return
        if scenario in {"http-500", "post-status-500"}:
            self._send(500, b"Server error\n", auth=auth, crumb=crumb, form=form, split=split, method="POST")
            return
        self.state.last_form = list(form)
        status = 302 if scenario in {"post-302", "trigger302"} else 201
        location = None
        if scenario == "post-location-missing":
            location = None
        elif scenario == "post-location-foreign":
            location = "http://example.invalid/queue/item/101/"
        elif scenario == "bad-location":
            location = "{}/queue/item/101/?x=1".format(self._origin())
        else:
            location = "{}/queue/item/101/".format(self._origin())
        headers = {"Location": location} if location else {}
        self._send(status, b"", headers, auth=auth, crumb=crumb, form=form, split=split, method="POST")

    def do_GET(self):
        split = urlsplit(self.path)
        if split.path == "/__shutdown":
            self._send(200, b"bye\n", split=split)
            self.state.stopping = True
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        if not self._auth_gate(split, "GET", []):
            return
        if split.path == "/crumbIssuer/api/json":
            self._crumb_get(split)
            return
        if self._job_get(split, split.path):
            return
        if self._queue_get(split, split.path):
            return
        if self._build_get(split, split.path):
            return
        self._send(404, b"Not found\n", split=split)

    def do_POST(self):
        split = urlsplit(self.path)
        length_text = self.headers.get("Content-Length", "0")
        try:
            length = max(0, int(length_text))
        except ValueError:
            length = 0
        raw = self.rfile.read(length)
        form = self._parse_form(raw)
        if not self._auth_gate(split, "POST", form):
            return
        if split.path.startswith("/job/") and split.path.endswith("/buildWithParameters"):
            self._trigger_post(split, form)
            return
        self._send(404, b"Not found\n", form=form, split=split, method="POST")


def _write_ready(path, port):
    if path is None:
        return
    target = Path(path)
    temporary = target.with_name(target.name + ".tmp-{}".format(os.getpid()))
    temporary.write_text(str(port) + "\n", encoding="ascii")
    os.chmod(str(temporary), 0o600)
    os.replace(str(temporary), str(target))


def _parse_args(argv):
    parser = argparse.ArgumentParser(description="loopback Jenkins fixture")
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--ready-file", "--port-file", dest="ready_file")
    parser.add_argument("--request-log")
    parser.add_argument("--mode", "--scenario", dest="mode", default="normal")
    return parser.parse_args(argv)


def main(argv=None):
    args = _parse_args(argv)
    if args.bind != "127.0.0.1":
        print("fake_jenkins.py only binds 127.0.0.1", file=sys.stderr)
        return 2
    if args.port < 0 or args.port > 65535:
        print("invalid port", file=sys.stderr)
        return 2
    mode = SCENARIO_ALIASES.get(args.mode, args.mode)
    if mode not in SCENARIOS:
        print("unknown fixture mode", file=sys.stderr)
        return 2
    request_log = None
    try:
        if args.request_log:
            request_log = open(args.request_log, "w", encoding="utf-8")
            os.chmod(args.request_log, 0o600)
        state = FixtureState(mode, request_log)
        server = FixtureServer(("127.0.0.1", args.port), Handler, state)
    except OSError as exc:
        if request_log is not None:
            request_log.close()
        print("fixture startup failed: {}".format(exc), file=sys.stderr)
        return 2

    def stop(_signum, _frame):
        state.stopping = True
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        _write_ready(args.ready_file, server.server_port)
    except OSError as exc:
        server.server_close()
        if request_log is not None:
            request_log.close()
        print("ready file failed: {}".format(exc), file=sys.stderr)
        return 2
    print("PORT={}".format(server.server_port), flush=True)
    print("READY", flush=True)
    try:
        server.serve_forever(poll_interval=0.05)
    finally:
        server.server_close()
        if request_log is not None:
            request_log.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
