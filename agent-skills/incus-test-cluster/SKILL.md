---
name: incus-test-cluster
description: Use when creating, resetting, accessing, or inspecting the local Longhorn test cluster, reproducing or verifying a fix on live VMs, or following instructions written for the deprecated tool/vagrant cluster.
---

# Incus test cluster

The local Longhorn test cluster is a disposable Incus VM cluster managed from
`tool/incus`: one K3s server, three workers, and Longhorn. It replaces the
deprecated `tool/vagrant` Vagrant/libvirt cluster; vagrant-libvirt is not
installed on this host, so translate Vagrant instructions with the table below.

## Sources of truth

- `tool/incus/cluster.yml.example`: every cluster requirement (Ubuntu, image
  source, K3s, Longhorn, IP family, storage network) and its allowed values.
  The ignored `tool/incus/cluster.yml` holds the user's current choice.
- `tool/incus/README.md`: lifecycle, networking, access, and teardown details.
- `cd tool/incus && mise tasks`: the available tasks.

## Environment

Run lifecycle tasks from `tool/incus`. The workspace environment (root
`mise.toml` and `.envrc`) sets:

- `KUBECONFIG` to `tool/incus/shared/k3s.config`, context `lh-incus`. Each
  provision rewrites the file and `down` deletes it.
- `INCUS_PROJECT=lh-incus`, so raw `incus` commands target the lab.

Before running kubectl against the cluster, confirm
`kubectl config current-context` prints `lh-incus`.

## Lifecycle

1. Preview with `mise run up --dry-run`: every check and the plan, no changes.
2. Create or converge with `mise run up`: init, apply, provision,
   verify. A fresh cluster takes about 7 minutes; an existing one about 2.
3. Tear down with `mise run down`: it force-stops and deletes the VMs,
   all data disks, the bridges, and the local cluster secrets, with no prompt.
   `mise run down --dry-run` lists what would go.

Run through your shell tool, these commands are quiet automatically: output
that is not a terminal goes to `tool/incus/.state/logs/`. You get one line per
step and a summary, or the failed task, the per-host errors, and the log tail.
Every run ends with `Full log: <path>`. Read that log only when the excerpt is
not enough, and search it with `grep` rather than reading it whole. Do not
pass `--verbose`: it streams several thousand lines into your context.

`up` is done when it exits 0. Then read its summary: Longhorn Node CR
problems are printed as `WARNING` lines and do not fail verify, because a
non-green node or disk can be the bug under test.

Flags such as `--longhorn master-head` or `--ip-family ipv6-dual` override
`cluster.yml` for one run and are not saved; repeat them on later
`provision` or `verify` runs. Changing `ubuntu`, `image_source`, `ip_family`,
or `storage_network`, or switching `longhorn` between a release and
`master-head`, needs `down` then `up`; the tool refuses it before planning.

## User consent

- Get the user's go-ahead before `mise run down` or `destroy`, or before a
  change that needs a fresh cluster, unless the task already asks for a fresh
  cluster: teardown deletes the cluster and all its data.
- Change `cluster.yml` only when the user asks; prefer per-run flags.

## Access

| Need | Command |
| --- | --- |
| Root shell | `mise run shell -- worker1` (default: `server`) |
| One command | `incus exec local:lh-incus-worker1 -- systemctl status k3s-agent` |
| Make a worker NotReady without killing Longhorn | `incus exec local:lh-incus-worker1 -- systemctl stop k3s-agent` |
| Copy files | `incus file push ./x.tar local:lh-incus-worker1/tmp/` or `incus file pull` |
| Boot log when the guest agent is down | `incus console local:lh-incus-worker1 --show-log` |
| VM state | `incus list local:` |

Nodes are `lh-incus-server` and `lh-incus-worker1` to `lh-incus-worker3`.
There is no SSH; the Incus guest agent carries every command.

## Custom container images

Full guide: "Custom container images" in `tool/incus/README.md`. Images must be
`linux/amd64` and named `repository:tag` with a tag other than `latest`;
an image in no registry needs an archive from `docker save` or `podman save`.

- Patched Longhorn component: declare it in `cluster.yml` under
  `longhorn_images` (keys `manager`, `engine`, `instance_manager`,
  `share_manager`, `backing_image_manager`, `ui`) and list its archive under
  `image_archives`, then run `mise run provision`. Provisioning imports the
  archives on every node and sets every reference, including the
  `longhorn-manager` DaemonSet arguments. Ask before editing `cluster.yml`.
- Any other image, or a quick experiment: for each VM, `incus file push` the
  archive to `/tmp` and run `incus exec local:<vm> -- k3s ctr images import
  /tmp/<archive>`. `k3s ctr` uses the `k8s.io` namespace that kubelet reads.
- Engine, instance-manager, share-manager, and backing-image-manager images
  come from `longhorn-manager` DaemonSet arguments (`--engine-image`,
  `--instance-manager-image`, `--share-manager-image`,
  `--backing-image-manager-image`), not their own pods. Swap them by hand by
  editing those arguments; the next provision restores the declared images.
- Attached volumes keep their running engine and instance manager until they
  are detached or upgraded. V2 instance managers take about two minutes to
  restart. For a clean result, detach volumes or recreate the cluster.

## Translating Vagrant instructions

| `tool/vagrant` | `tool/incus` |
| --- | --- |
| `vagrant up` | `mise run up` |
| `vagrant destroy -f` | `mise run down` |
| `vagrant ssh <vm> -- <cmd>` | `incus exec local:<vm> -- <cmd>` |
| `vagrant status` | `incus list local:` |
| `vagrant halt <vm>` / `vagrant reload <vm>` | `incus stop local:<vm>` / `incus restart local:<vm>` |
| `libvirt-ubuntu-k3s-master`, `libvirt-ubuntu-k3s-worker<N>` | `lh-incus-server`, `lh-incus-worker<N>` |
| `shared/libvirt-ubuntu-k3s.config` | `tool/incus/shared/k3s.config` |
| `/vagrant_shared` folder | `incus file push` / `pull` |
| `network_stack`, `enable_storage_network` in `Vagrantfile` | `ip_family`, `storage_network` in `cluster.yml` |

## Known behavior

- Longhorn comes from a release through Helm, or `master-head` from the
  master branch manifest, with any `longhorn_images` replacements applied.
- `verify` leaves out two false negatives in these VMs: `HugePagesAvailable`
  while V2 hugepages are disabled, and `HealthDataCollected` because virtual
  disks have no SMART support.
- If VMs boot-loop before the guest agent starts, set `image_source: official`
  and run `mise run image:import`; see `tool/incus/docs/official-ubuntu-image.md`.
- Reset with `mise run down`, never by running `tofu apply` directly or by
  deleting `tool/incus/.state/`.
- Past live runs and their findings: `tool/incus/docs/live-validation.md`.
