# Solo User Questions: Full Analysis

> **Date:** 2026-02-03
> **Source:** Cross-team user feedback on Solo adoption
> **Solo Version Analyzed:** 0.53.0 (repo at `repos/solo`)
> **Status:** Local review draft -- not for publication

---

## Table of Contents

- [Overview](#overview)
- [Features Teams May Already Be Unaware Of](#features-teams-may-already-be-unaware-of)
- [Question-by-Question Analysis](#question-by-question-analysis)
  - [Q1: Startup Time (10+ min, want 10-40s)](#q1-startup-time)
  - [Q2: Service Toggles (disable relay/mirror)](#q2-service-toggles)
  - [Q3: Large Initial Balances + Auto-Funded EVM Accounts](#q3-large-initial-balances)
  - [Q4: gRPC Proxy + Mirror Endpoints Broken](#q4-grpc-proxy--mirror-endpoints)
  - [Q5: one-shot falcon on GH Actions Timeout](#q5-one-shot-falcon-on-gh-actions)
  - [Q6: Simplicity Like Hardhat/Foundry](#q6-simplicity-like-hardhatfoundry)
  - [Q7: CLI Env Vars / SOLO_DEPLOYMENT](#q7-cli-env-vars)
  - [Q8: Log Streaming](#q8-log-streaming)
  - [Q9: Version Management](#q9-version-management)
  - [Q10: Architecture Docs](#q10-architecture-docs)
  - [Q11: Post-Command Lag (30-60s)](#q11-post-command-lag)
  - [Q12: Local Node Migration Questions](#q12-local-node-migration)
- [Current Best-Practices Guide](#current-best-practices-guide)
  - [Startup Optimization](#startup-optimization)
  - [Minimal Stack for EVM Testing](#minimal-stack-for-evm-testing)
  - [Account Setup](#account-setup)
  - [Port Forwarding Recovery](#port-forwarding-recovery)
  - [CI Workflow](#ci-workflow)
  - [Log Streaming Without kubectl Expertise](#log-streaming-without-kubectl-expertise)
  - [Deployment Name Management](#deployment-name-management)
  - [Version Checking](#version-checking)
  - [Test Configuration for Solo](#test-configuration-for-solo)
- [Proposed GitHub Issues](#proposed-github-issues)
  - [High Priority Issues](#high-priority-issues)
  - [Medium Priority Issues](#medium-priority-issues)
  - [Lower Priority Issues](#lower-priority-issues)
- [Summary Matrix](#summary-matrix)
- [Migration Status](#migration-status)

---

## Overview

Twelve questions were collected from teams working with Solo. After thorough analysis
of the Solo codebase (v0.53.0), its Hugo documentation site, the hedera-evm-lab
test reports, and the Local Node migration status, each question falls into one of
three categories:

1. **Awareness gap** -- the capability exists in Solo today but teams don't know
   about it or it's poorly surfaced in docs.
2. **Workflow gap** -- a reasonable workflow exists today using existing commands but
   it requires non-obvious steps or kubectl knowledge.
3. **Feature gap** -- Solo genuinely lacks the capability and a GitHub issue should
   be filed.

Most questions are a mix of all three.

---

## Features Teams May Already Be Unaware Of

This is the lowest-hanging fruit. Several user complaints map to features that
**already exist** but aren't surfaced well in docs or aren't being used by teams.

### Already Exists But Underused

| User Complaint | Existing Feature | Where It Lives | Gap |
|---|---|---|---|
| "Need to disable relay/mirror" | `--minimal-setup` flag on one-shot | `flags.ts` / `default-one-shot.ts:434` | Skips explorer+relay but not mirror. Still, it's a start. |
| "Need auto-funded EVM accounts" | 30 predefined accounts created automatically by one-shot (10 ECDSA-with-alias, 10,000 HBAR each, private keys displayed) | `predefined-accounts.ts` | Keys scroll past in terminal output. Users may not realize they're there. |
| "Hide Kubernetes steps" | `solo one-shot single deploy` already auto-creates cluster, namespace, deployment, keys | `default-one-shot.ts` | The command name itself isn't discoverable -- needs `solo start` alias. |
| "Show deployment name" | One-shot caches the deployment name to `~/.solo/cache/last-one-shot-deployment.txt` | `default-one-shot.ts:513` | No command to retrieve it later. |
| "Show installed component versions" | `solo --version -o json` shows CLI version; env vars document all component version defaults | `version.ts`, `env.md` | Doesn't show deployed component versions, only defaults. |
| "Env var for deployment" | `SOLO_DEPLOYMENTS_0_NAME=deployment1` works via `EnvironmentStorageBackend` | `environment-storage-backend.ts` | The env var format is `SOLO_DEPLOYMENTS_0_NAME`, **not** `SOLO_DEPLOYMENT`. This is undocumented for CLI users. |
| "Resource guidance for CI" | `solo-ci-workflow.md` documents 6 CPU / 12 GB minimum | `docs/site/content/en/docs/solo-ci-workflow.md` | Doesn't specify per-component minimums or GH Actions runner type recommendations. |
| "Diagnostics without kubectl" | `solo deployment diagnostics connections` tests all endpoints; `solo deployment diagnostics logs` downloads consensus logs | `deployment-command-definition.ts` | No relay/mirror log streaming. Only batch download of consensus logs. |
| "Manual step-by-step for custom stacks" | Full command set exists: `solo consensus network deploy`, `solo mirror deploy`, `solo relay deploy` independently | `solo-cli.md`, `solo-with-mirror-node.md` | The step-by-step path is documented but hard to discover; users default to one-shot. |
| "Timeout tuning for CI" | 20+ env vars control timeouts: `PODS_RUNNING_MAX_ATTEMPTS`, `RELAY_PODS_READY_MAX_ATTEMPTS`, etc. | `env.md` | No "preset" profiles; users must discover and set each individually. |
| "`hiero-solo-action` for GH Actions" | Official GitHub Action exists, already used by hiero-sdk-js and hiero-sdk-rust | `local-node-migration-status.csv` | Not mentioned in Solo's own CI docs. Not adopted by most repos. |
| "Pinger for mirror node freshness" | `--pinger` flag on mirror deploy keeps record files flowing | `solo-with-mirror-node.md` | Not enabled by default on one-shot. Without it, mirror node may appear stale. |

### Key Awareness Actions (no code changes needed)

1. **Document the predefined accounts prominently.** After one-shot completes, users
   get 10 ECDSA-alias accounts at `0.0.1002`+ with 10,000 HBAR each. Private keys
   in `0x` format are printed but scroll past. A `solo deployment accounts` command
   or a file output would help.

2. **Document `SOLO_DEPLOYMENTS_0_NAME`** as the correct env var format for
   deployment names (not `SOLO_DEPLOYMENT`). The `start-solo.sh` script in evm-lab
   uses `SOLO_DEPLOYMENT` as a shell variable for the `--deployment` flag, which is
   different from Solo's internal env var system.

3. **Promote `hiero-solo-action`** in the CI workflow docs. The repos that have
   converted (hiero-sdk-js, hiero-sdk-rust) use this action and it handles Kind
   cluster setup, Solo installation, and deployment.

4. **Document `--minimal-setup`** with clear explanation of what it skips (explorer,
   relay) and what it keeps (consensus, mirror).

---

## Question-by-Question Analysis

---

<a id="q1-startup-time"></a>
### Q1: Startup Time (10+ min, want 10-40s, smaller memory)

> Solo startup currently takes 10+ minutes for 1-2 node clusters (both locally and
> on GH Actions), preventing rapid test iterations, forcing long CI timeouts, and
> demanding high-spec machines; teams want optimizations and guidance to reach 10-40s
> startup and smaller memory footprints comparable to Local Node.

#### What the User Is Attempting

Rapid test iteration cycles where the network starts quickly (comparable to Local
Node's ~57s or Hardhat's instant startup), enabling developers to spin up/down
networks per test suite or PR check.

#### What Solo Currently Provides

- `solo one-shot single deploy` takes **10-12 minutes** on an M-series Mac (711.5s
  measured in test reports at `reports/2026-01-28_14-59-48_both-test-report.md`).
- Minimum resources: **6 CPU cores, 12 GB RAM** (documented in
  `docs/site/content/en/docs/solo-ci-workflow.md`).
- Bottlenecks in order: pod scheduling (~48s), relay deploy (~40s), consensus node
  start (~38s), mirror node startup, Helm chart installation, image pulls.
- There is a `--minimal-setup` flag on one-shot commands that **skips explorer and
  relay** (`src/commands/one-shot/default-one-shot.ts:434`), which shaves off
  ~60-80s but doesn't fundamentally change the timeline.
- Timeout env vars exist (`PODS_RUNNING_MAX_ATTEMPTS=900`,
  `PODS_RUNNING_DELAY=1000ms`) but these are upper bounds, not causes of slowness.

#### Most Efficient Current Workflow

1. **Don't destroy between test runs.** Start Solo once, run all test suites against
   the running network, only destroy when done. The `start-solo.sh` script already
   checks if a cluster exists and skips creation.
2. Use `--minimal-setup` if you don't need explorer/relay for a specific test.
3. Pre-pull Docker images to a local cache (`docker pull` the consensus node, mirror,
   relay images before running Solo).
4. For CI, use a **shared Kind cluster** across workflow steps rather than
   creating/destroying per job.

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-fast-restart`** | Implement a "warm restart" mode that preserves the Kind cluster and Helm releases but resets consensus state (wipe PVCs, re-init accounts). Target: <60s restart. |
| **`solo-image-preload`** | Add `solo cluster preload` command that pulls all required images into the Kind cluster ahead of deployment, removing image pull time from the critical path. |
| **`solo-startup-profiling`** | Instrument and publish a startup timing breakdown so each phase (cluster, charts, pods, readiness) can be independently optimized. The evm-lab already has timing instrumentation in `scripts/start-solo.sh` that could be upstreamed. |
| **`solo-resource-profiles`** | The `--profile` flag exists (local/small/medium/large) but isn't well-documented for memory reduction. Document recommended profiles for constrained environments and optimize the "local" profile for minimum footprint. |

---

<a id="q2-service-toggles"></a>
### Q2: Service Toggles (disable relay/mirror, CN+relay-only mode)

> Need toggles to disable unused services (e.g., relay, mirror) and even a
> single-binary or CN+relay-only mode so EVM tests can run a minimal stack; Solo
> and EVM teams should align on control plane/memory optimizations to support this.

#### What the User Is Attempting

Running only a consensus node + JSON-RPC relay for pure EVM testing, skipping mirror
node, explorer, block node, and MinIO to reduce memory and startup time.

#### What Solo Currently Provides

- `--minimal-setup` flag: skips **explorer and relay** but still deploys mirror node
  (which is the opposite of what EVM teams want -- they want relay but not mirror).
- Individual component commands exist: `solo mirror deploy`, `solo relay deploy`,
  `solo explorer deploy` are separate commands. You can skip them by not running them.
- The `one-shot falcon deploy --values-file` mode gives full Helm-level control over
  what gets deployed.
- `--minio` flag (default: true) can be set to false.
- `--json-rpc-relay` flag exists on some commands.
- Block node controlled by `ONE_SHOT_WITH_BLOCK_NODE` env var (default: false).

#### Most Efficient Current Workflow

Use the **manual step-by-step deployment** instead of one-shot:

```bash
solo cluster setup --cluster-ref solo
solo deployment config create --namespace solo --deployment solo-deployment
solo deployment cluster attach --deployment solo-deployment --cluster-ref solo
solo keys consensus generate --deployment solo-deployment --gossip-keys --tls-keys
solo consensus network deploy --deployment solo-deployment
solo consensus node setup --deployment solo-deployment
solo consensus node start --deployment solo-deployment
# Deploy ONLY relay, skip mirror/explorer/block:
solo relay deploy --deployment solo-deployment --node-aliases node1
```

Or use `one-shot falcon deploy` with a values file that disables mirror/explorer.

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-evm-mode`** | Add a `--evm-only` or `--mode evm` flag to one-shot that deploys only consensus node + relay (the minimum for `eth_sendRawTransaction` and `eth_call`). Note: relay currently depends on mirror node for historical queries, so this requires either a relay change or accepting that only real-time operations work. |
| **`solo-minimal-redesign`** | Redesign `--minimal-setup` to mean "consensus only" and add `--with-relay`, `--with-mirror`, `--with-explorer` additive flags instead of the current subtractive model. |
| **`solo-service-toggle-docs`** | Document how to compose a minimal stack using the step-by-step commands or falcon values file, with memory estimates for each combination. |

---

<a id="q3-large-initial-balances"></a>
### Q3: Large Initial Balances + Auto-Funded EVM Accounts

> Provide configuration for large initial balances (~1M HBAR) on static accounts
> plus automatic, funded EVM accounts (with optional EVM aliases and private keys
> shown) immediately after quick-start so repeated integration tests don't stall.

#### What the User Is Attempting

Starting Solo and immediately having accounts with ~1M HBAR, ECDSA keys with EVM
aliases, and private keys displayed -- so integration tests can run without funding
stalls or additional `account create` calls.

#### What Solo Currently Provides

- **Predefined accounts are already created** by one-shot: 30 accounts (10 ECDSA,
  10 ECDSA-with-alias, 10 ED25519) each with **10,000 HBAR**
  (`src/commands/one-shot/predefined-accounts.ts:26`).
- Private keys **are displayed** in `0x` EVM format after deployment
  (`default-one-shot.ts:673-696`).
- The ECDSA-alias accounts have `alias: true` set, meaning they have EVM-compatible
  addresses.
- The `--hbar-amount` flag on `ledger account create` allows specifying funding
  amounts.
- Operator account `0.0.2` has the genesis key and treasury balance.

#### Gap

The default 10,000 HBAR per account may be insufficient for heavy integration
testing. There is no flag on one-shot to override the predefined account balance.
The hardcoded `Hbar.from(10_000, HbarUnit.Hbar)` in `predefined-accounts.ts:26` is
not configurable.

#### Most Efficient Current Workflow

1. Run `solo one-shot single deploy` -- get 30 pre-funded accounts automatically.
2. If you need more HBAR, create additional accounts post-deployment:
   ```bash
   solo ledger account create --deployment solo-deployment \
     --hbar-amount 1000000 --generate-ecdsa-key --set-alias
   ```
3. For CI, script a loop that creates N accounts with desired balances after one-shot
   completes.

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-predefined-balance-flag`** | Add `--predefined-account-balance` flag to one-shot commands so users can set initial balance (e.g., `--predefined-account-balance 1000000`). Currently hardcoded at 10,000 HBAR in `predefined-accounts.ts:26`. |
| **`solo-account-config-file`** | Support a JSON/YAML file defining custom accounts (count, balance, key type, alias) that one-shot reads during deployment. Enables repeatable CI setups without post-deploy scripts. |
| **`solo-display-accounts-command`** | Add `solo deployment accounts` command that re-displays all pre-funded account info (addresses, private keys, balances) for a running deployment, since terminal output scrolls past. |

---

<a id="q4-grpc-proxy--mirror-endpoints"></a>
### Q4: gRPC Proxy + Mirror REST/gRPC Endpoints Broken

> Solo should expose gRPC proxy (including second node) and mirror REST/gRPC
> endpoints automatically; current gRPC proxy forwarding is broken and `one-shot`
> deployments lose the 50211 port-forward soon after start, forcing manual kubectl
> work.

#### What the User Is Attempting

After one-shot deploy, connecting via Hedera SDK (gRPC on 50211), mirror REST
(8081), and mirror gRPC (5600) -- all automatically forwarded to localhost.

#### What Solo Currently Provides

- Port forwarding is **enabled by default** (`--force-port-forward` defaults to
  `true` in `flags.ts`).
- A persistent port-forward script exists at
  `src/integration/kube/k8-client/resources/pod/persist-port-forward.ts` with
  auto-reconnection and exponential backoff.
- After one-shot deploy, the code calls `showPortForwards()`
  (`default-one-shot.ts:511`) which displays forwarded ports.
- The deployment caches port-forward info to
  `constants.PORT_FORWARDING_MESSAGE_GROUP`.
- Documented endpoints: JSON-RPC 7546, Mirror REST 8081, Explorer 8080, gRPC 50211.

#### Known Problem

The port-forward processes are spawned as child processes of the Solo CLI. When the
CLI exits (one-shot completes), these child processes may terminate depending on how
they're managed. The `persist-port-forward.ts` script is designed to survive, but
users report that **50211 disappears after one-shot finishes**.

#### Most Efficient Current Workflow

If port forwards die, manually re-establish them:

```bash
# Re-establish gRPC proxy
kubectl port-forward -n solo svc/haproxy-node1-svc 50211:50211 &

# Re-establish mirror REST
kubectl port-forward -n solo svc/mirror-rest 8081:80 &

# Re-establish mirror gRPC
kubectl port-forward -n solo svc/mirror-grpc 5600:5600 &

# Re-establish relay
kubectl port-forward -n solo svc/relay-node1-hedera-json-rpc-relay 7546:7546 &
```

Wrap this in a script for your team. The evm-lab's `start-solo.sh` already
health-checks the relay after deployment.

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-port-forward-persistence`** | Investigate and fix port-forward lifecycle after one-shot exits. Port forwards should persist as background processes (or be daemonized) independent of the CLI process. Consider writing PID files to `~/.solo/` for management. |
| **`solo-port-forward-reconnect`** | Add `solo deployment port-forward` command that re-establishes all port forwards for a named deployment, reading from cached deployment state. |
| **`solo-grpc-second-node`** | When deploying multi-node, automatically forward gRPC for node2 (50212) and subsequent nodes, not just node1. |
| **`solo-endpoint-status`** | Add `solo deployment status` command showing all forwarded ports and their health (connected/disconnected), similar to `docker ps` output. |

---

<a id="q5-one-shot-falcon-on-gh-actions"></a>
### Q5: one-shot falcon on GH Actions (15-min timeout, relay pod failures)

> `npx @hashgraph/solo one-shot falcon deploy` on GitHub Actions often exceeds a
> 15-minute timeout and can fail because the relay pod never becomes ready; CI users
> need clearer resource guidance or improved stability for one-shot workflows.

#### What the User Is Attempting

Running `npx @hashgraph/solo one-shot falcon deploy` in GitHub Actions CI, but
hitting 15-minute timeouts because the relay pod never reaches Ready state.

#### What Solo Currently Provides

- CI docs (`solo-ci-workflow.md`) specify minimum 6 CPU / 12 GB RAM.
- Relay pod readiness is governed by:
  - `RELAY_PODS_RUNNING_MAX_ATTEMPTS=900` x `RELAY_PODS_RUNNING_DELAY=1000ms` =
    15 min max wait
  - `RELAY_PODS_READY_MAX_ATTEMPTS=100` x `RELAY_PODS_READY_DELAY=1000ms` = 100s
    max wait
- GitHub Actions `ubuntu-latest` runners provide 2 CPU / 7 GB RAM -- **well below
  Solo's minimum requirements**.
- Even `ubuntu-latest-8-cores` may not have enough memory.
- The `npx` invocation downloads Solo fresh each time, adding startup overhead.

#### Most Efficient Current Workflow

1. Use **larger runners**: `runs-on: ubuntu-latest` is insufficient. Need custom
   runners or self-hosted with adequate specs.
2. Pre-install Solo globally instead of `npx`:
   `npm install -g @hashgraph/solo@0.53.0`.
3. Use `--minimal-setup` to skip explorer/relay if not needed for the specific test.
4. Reduce timeout env vars for faster failure detection rather than waiting 15 min:
   ```bash
   export RELAY_PODS_RUNNING_MAX_ATTEMPTS=300
   export PODS_READY_MAX_ATTEMPTS=120
   ```
5. Use `hiero-ledger/hiero-solo-action` GitHub Action (already used by hiero-sdk-js
   and hiero-sdk-rust per migration status CSV) which handles setup correctly.

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-ci-resource-matrix`** | Publish an official resource matrix: (a) minimum for consensus-only, (b) minimum for consensus+relay, (c) minimum for full stack, (d) recommended for CI. Include GitHub Actions runner type recommendations. |
| **`solo-relay-readiness-diagnostics`** | When relay pod fails to become ready, Solo should dump relay pod logs and events automatically, rather than silently timing out. Add `--verbose-on-failure` behavior. |
| **`solo-falcon-ci-example`** | Add a tested GitHub Actions workflow example for falcon deploy with documented runner specs, timeouts, and resource allocations. |
| **`solo-timeout-presets`** | Add `--timeout-profile fast\|normal\|patient` flag that sets all timeout env vars to appropriate values, so CI users don't need to set 10+ env vars individually. |

---

<a id="q6-simplicity-like-hardhatfoundry"></a>
### Q6: Simplicity Like Hardhat/Foundry

> Solo should feel as simple as Hardhat/Foundry: one command launches the full stack
> on current preview/test/main versions, hides Kubernetes steps, yields a
> ready-to-use environment (accounts included), shows the deployment name, and runs
> acceptably even on low-RAM hardware.

#### What the User Is Attempting

Running something like `solo start` and getting a fully working Hedera network
without knowing about Kind, kubectl, Helm, namespaces, or pods. Similar to how
`npx hardhat node` just works.

#### What Solo Currently Provides

- `solo one-shot single deploy` is the closest: one command that creates cluster,
  namespace, deployment, keys, consensus, mirror, explorer, relay.
- It auto-generates deployment names (`solo-deployment-{uuid}`).
- It displays endpoints and pre-funded accounts after completion.
- But: it requires Docker, Kind, and kubectl pre-installed. It takes 10+ minutes.
  Output is verbose Listr2 task trees, not clean endpoint summaries.

#### Gap

There is no `solo start` / `solo stop` simplicity layer. Users must understand
`one-shot single deploy` vs `one-shot multi deploy` vs `one-shot falcon deploy`.
The deployment name is auto-generated and hard to remember. Kubernetes concepts leak
into error messages and logs.

#### Most Efficient Current Workflow

The `scripts/start-solo.sh` in hedera-evm-lab is essentially a wrapper that provides
this experience:

```bash
./scripts/start-solo.sh
# -> checks prereqs, creates cluster if needed, runs one-shot, health-checks, prints endpoints
```

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-start-stop`** | Add `solo start` and `solo stop` as top-level aliases for `one-shot single deploy` and `one-shot single destroy`. These should be the documented entry point for new users. |
| **`solo-clean-output`** | After deployment, print a clean summary block with endpoints, accounts, and deployment name -- separate from the verbose task output. Consider a `--quiet` mode that only shows the summary. |
| **`solo-prereq-installer`** | Add `solo doctor` command that checks for Docker/Kind/kubectl and offers to install missing dependencies (via Homebrew on macOS, apt on Linux). The evm-lab already has `scripts/doctor.sh` that does this. |
| **`solo-default-deployment-name`** | Use a deterministic default deployment name like `solo-deployment` (not UUID-suffixed) for one-shot single, so users can always reference it without looking it up. Only add UUID for multi-deployment scenarios. |

---

<a id="q7-cli-env-vars"></a>
### Q7: CLI Env Vars / SOLO_DEPLOYMENT

> CLI should honor env vars such as `SOLO_DEPLOYMENT`, allow default
> node-alias/deployment overrides without repeated flags, and avoid forcing users
> through manual kind/kubectl flows; today `solo account create` still errors with
> "Deployment not found" even when the env var is set.

#### What the User Is Attempting

Setting `SOLO_DEPLOYMENT=my-deployment` as an env var and having all subsequent
`solo` commands use it without passing `--deployment` every time. Also:
`solo account create` failing with "Deployment not found" even when the env var is
set.

#### What Solo Currently Provides

- The `--deployment` flag (`flags.ts:1947`) has **no `envKey` mapping**. Its
  `defaultValue` is an empty string `''`.
- Solo does have an `EnvironmentStorageBackend`
  (`src/data/backend/impl/environment-storage-backend.ts`) that reads
  `SOLO_DEPLOYMENTS_0_NAME=deployment1` style env vars, but this is for the internal
  config system, not for CLI flag defaults.
- The CI workflow docs reference `SOLO_DEPLOYMENT` as a shell variable used in
  scripts, not as something Solo's CLI reads.
- When `--deployment` is empty and no deployment exists in local config, commands
  fail with deployment-not-found errors.
- The one-shot command caches the deployment name to
  `~/.solo/cache/last-one-shot-deployment.txt` (`default-one-shot.ts:513`), but this
  isn't read by other commands as a default.

#### This Is a Legitimate Gap

The `--deployment` flag should support an env var fallback, and the cached last
deployment name should be used as a default.

#### Most Efficient Current Workflow

Always pass `--deployment` explicitly:

```bash
export DEPLOY_NAME="solo-deployment"
solo ledger account create --deployment $DEPLOY_NAME --hbar-amount 1000 --generate-ecdsa-key
```

Or use a shell alias:

```bash
alias solo='solo --deployment solo-deployment'
```

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-deployment-env-var`** | Make `--deployment` flag read from `SOLO_DEPLOYMENT` env var as a fallback. This is the #1 ergonomic improvement for repeat CLI usage. |
| **`solo-default-deployment`** | When no `--deployment` is provided and no env var is set, auto-detect from: (1) `~/.solo/cache/last-one-shot-deployment.txt`, (2) if exactly one deployment exists in local config, use it. |
| **`solo-node-alias-default`** | Similarly, `--node-aliases` should default to `node1` for single-node deployments, avoiding the need to pass `-i node1` on every command. |
| **`solo-context-command`** | Add `solo context set --deployment X` that persists a default deployment, similar to `kubectl config use-context`. |

---

<a id="q8-log-streaming"></a>
### Q8: Log Streaming

> Need an easy `solo` command to stream JSON-RPC relay or mirror importer logs so
> devs can debug without digging into Kubernetes.

#### What the User Is Attempting

Running a single `solo` command to tail JSON-RPC relay logs or mirror node importer
logs in real-time, without needing to know pod names or kubectl syntax.

#### What Solo Currently Provides

- `solo deployment diagnostics logs` -- downloads consensus node logs to a local
  directory (batch download, not streaming).
- `solo deployment diagnostics connections` -- tests connectivity to all components.
- `solo consensus node logs` -- downloads node logs to `--output-dir`.
- **No streaming/tailing capability exists in the CLI.**
- Application logs are also written to `~/.solo/logs/solo.log` and
  `~/.solo/logs/hashgraph-sdk.log`, but these are Solo CLI logs, not component logs.

#### Most Efficient Current Workflow

Use kubectl directly:

```bash
# Stream relay logs
kubectl logs -n solo -l app=hedera-json-rpc-relay -f

# Stream mirror importer logs
kubectl logs -n solo -l app.kubernetes.io/component=importer -f

# Stream consensus node logs
kubectl logs -n solo -l app=network-node -c root-container -f
```

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-logs-command`** | Add `solo logs <component> [--follow]` command where component is one of: `relay`, `mirror`, `mirror-importer`, `consensus`, `explorer`, `block`. Maps to the correct pod label selector and container. `--follow` enables streaming (kubectl logs -f). |
| **`solo-logs-all`** | Add `solo logs --all` that multiplexes logs from all components with prefixed output (like `docker compose logs`). |

---

<a id="q9-version-management"></a>
### Q9: Version Management

> Quick-start should use up-to-date preview/test/mainnet tags,
> `solo node/relay upgrade` with no args should apply the newest compatible versions
> while warning about mismatches, CLI should show installed component versions, and
> Hashgraph should publish an official Solo-to-Local Node parity/compatibility matrix
> plus a plan to align Solo releases with public networks.

#### What the User Is Attempting

Running `solo node upgrade` or `solo relay upgrade` without specifying a version and
having it automatically pull the latest compatible version. Also: knowing which Solo
version maps to which network version.

#### What Solo Currently Provides

- `solo --version` displays the Solo CLI version (0.53.0). Supports
  `-o json|yaml|wide`.
- Default component versions are hardcoded in `src/version.ts` and overridable via
  env vars (`CONSENSUS_NODE_VERSION`, `MIRROR_NODE_VERSION`, `RELAY_VERSION`, etc.).
- Current defaults: Platform v0.67.2, Mirror v0.145.2, Relay v0.73.0, Explorer
  v25.1.1, Block Node v0.23.2.
- Upgrade commands exist: `solo consensus network upgrade`, `solo mirror upgrade`,
  `solo relay upgrade`, `solo explorer upgrade`.
- These **require** explicit version flags (e.g., `--upgrade-version`,
  `--relay-release-tag`). There is no "upgrade to latest" mode.
- No compatibility matrix is published.
- The `env.md` docs show component version defaults but these may lag behind public
  network versions.

#### Most Efficient Current Workflow

Check public network versions manually, then:

```bash
solo relay upgrade --deployment solo-deployment --relay-release-tag v0.73.0
solo mirror upgrade --deployment solo-deployment --mirror-node-version v0.145.2
```

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-version-info`** | Add `solo version --components` that displays all component versions (Solo CLI + consensus + mirror + relay + explorer + block node) for the current deployment. |
| **`solo-upgrade-latest`** | When no version is specified on upgrade commands, fetch the latest compatible version from a published compatibility manifest (could be a JSON file in the Solo repo or OCI registry). Warn if the upgrade crosses a major version boundary. |
| **`solo-compatibility-matrix`** | Publish and maintain a Solo version <-> component version <-> public network version matrix. This should be in the docs site and machine-readable (JSON). |
| **`solo-version-check`** | Add `solo version check` that compares deployed component versions against latest available and warns about outdated components, similar to `npm outdated`. |
| **`solo-release-parity`** | Establish a release cadence that ensures Solo defaults are updated within N days of a public network upgrade, with release notes documenting the version bump. |

---

<a id="q10-architecture-docs"></a>
### Q10: Architecture Docs

> Provide architecture diagrams and plain-language docs that explain which services
> quick-start installs, why Docker/Node/Kubernetes are required, and clearly
> differentiate pods/deployments/cluster nodes from Hedera consensus nodes to help
> JS/TS devs without DevOps backgrounds.

#### What the User Is Attempting

Understanding what `solo one-shot single deploy` actually installs, why
Docker/Kind/kubectl are needed, and what the difference is between a Kubernetes pod,
a Kubernetes node, a Hedera consensus node, and a deployment.

#### What Solo Currently Provides

- The FAQ (`docs/site/content/en/docs/faq.md`) explains the one-shot modes and key
  management but doesn't include architecture diagrams.
- The CI workflow doc explains resource requirements but not architecture.
- The evm-lab quickstart (`docs/09-solo-quickstart-deploy-and-explore.md`) explains
  the data flow (Consensus -> Mirror -> Relay -> Explorer) in text form.
- **No architecture diagrams exist** in the Solo docs site.
- **No glossary** differentiating Kubernetes concepts from Hedera concepts exists.

#### What the evm-lab Already Provides (and Could Be Upstreamed)

- `docs/02-solo-vs-local-node-gap-analysis.md` has a clear architecture comparison.
- `docs/09-solo-quickstart-deploy-and-explore.md` has a "Why 120-Second Timeout?"
  section explaining the network topology.

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-architecture-diagram`** | Create and publish an architecture diagram showing: Host OS -> Docker -> Kind (Kubernetes) -> Pods (consensus node, mirror importer, mirror REST, relay, explorer, MinIO). Show port forwarding from localhost to pods. |
| **`solo-glossary`** | Add a glossary page to the docs: Kubernetes cluster vs Hedera network, pod vs consensus node, deployment (k8s) vs deployment (Solo), namespace, Kind, Helm chart. |
| **`solo-prereq-explainer`** | Add a "Why These Prerequisites?" doc page explaining: Docker (container runtime), Kind (local Kubernetes), kubectl (Kubernetes CLI), Helm (package manager for k8s). Target audience: JS/TS developers who've never used Kubernetes. |
| **`solo-data-flow-doc`** | Document the transaction lifecycle: Client -> gRPC Proxy (50211) -> Consensus Node -> Record Stream -> Mirror Importer -> PostgreSQL -> Mirror REST (8081) -> Explorer (8080), and separately Client -> Relay (7546) -> Consensus Node for EVM transactions. |

---

<a id="q11-post-command-lag"></a>
### Q11: Post-Command Lag (30-60s)

> After running commands such as `solo account create`, control returns to the shell
> 30-60s later even though the action finished; this lag needs to be eliminated.

#### What the User Is Attempting

Running `solo ledger account create` and having control return to the shell
immediately after the account is created.

#### What Solo Currently Provides

- Account creation uses Listr2 for task management.
- After the account is created and funded, the CLI performs cleanup tasks: closing
  SDK client connections, releasing Kubernetes resources, writing to local config.
- The `NODE_CLIENT_REQUEST_TIMEOUT` is 600,000ms (10 minutes).
- `NODE_CLIENT_PING_INTERVAL` is 30,000ms.
- `SOLO_LEASE_DURATION` is 20 seconds (distributed lock).
- The SDK client (`NodeClient`) pings consensus nodes at 30s intervals and may wait
  for graceful shutdown.

#### Root Cause Hypothesis

The 30-60s lag is likely the SDK client graceful shutdown waiting for in-flight pings
to complete or the lease release timeout. The `NODE_CLIENT_PING_INTERVAL=30000` and
`SOLO_LEASE_DURATION=20` together could account for this.

#### Most Efficient Current Workflow

No known workaround other than backgrounding the command:

```bash
solo ledger account create --deployment solo-deployment --hbar-amount 1000 \
  --generate-ecdsa-key &
wait $!
```

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-fast-exit`** | Profile and fix the post-command cleanup delay. Likely causes: (1) SDK client graceful close waiting for ping timeout, (2) lease release delay, (3) config write I/O. The client close should be non-blocking with a short timeout (2-3s max). |
| **`solo-client-shutdown-timeout`** | Add a `SOLO_CLIENT_SHUTDOWN_TIMEOUT` env var (default: 3s) that caps how long the CLI waits for SDK client graceful shutdown before force-closing. |

---

<a id="q12-local-node-migration"></a>
### Q12: Local Node Migration Questions

> Product teams need clarity on: the technical blockers keeping Local Node from
> supporting Block Streams, the effort to upgrade Local Node vs. moving users,
> telemetry on current Local Node vs. Solo adoption, top workflows relying on Local
> Node (e.g., CI), which user segments will be most disrupted (hackathons, secure
> enterprises, CI, Windows, low-RAM), the OS/hardware support matrix and minimum
> specs for Solo, alternatives for developers who can't run Kubernetes (remote
> clusters or a "lite" mode), how debugging/troubleshooting flows will change, how
> Solo releases will stay in parity with public networks, whether a conversion tool
> from Local Node to Solo is feasible, and if a compatibility mode is needed to
> preserve ports/account IDs/URLs.

#### What the User Is Attempting

Getting clarity on the full migration strategy from Local Node to Solo across all
user segments.

#### What Solo/evm-lab Currently Provides

**Migration status data** (`local-node-migration-status.csv`):
- **4 repos converted** to Solo: hiero-block-node, hiero-sdk-js, hiero-sdk-rust,
  hedera-transaction-tool
- **21+ repos NOT converted**: hiero-json-rpc-relay (6 workflows),
  hedera-smart-contracts (3 workflows), stablecoin-studio, hedera-cli,
  hedera-sourcify, hedera-forking, etc.

**Gap analysis** (`docs/02-solo-vs-local-node-gap-analysis.md`):
- EVM feature parity: 100% identical between Solo and Local Node
- Solo startup: 12.3x slower than Local Node (711s vs 57s)
- Solo memory: 50% higher minimum (12GB vs 8GB)
- Solo provides better production parity and multi-node support
- Local Node has faster mirror node sync (filesystem shortcut vs network hop)

#### What's Documented vs. What's Missing

| Question | Status |
|----------|--------|
| Block Stream technical blockers for Local Node | **Not documented** -- needs Hedera engineering input |
| Effort to upgrade Local Node vs. moving users | **Not documented** -- product/engineering decision |
| Telemetry on Local Node vs Solo adoption | **Not documented** -- only the CSV migration status exists as a proxy |
| Top workflows relying on Local Node | **Partially documented** -- CSV shows 21+ unconverted repos, mostly CI |
| Most disrupted user segments | **Not documented** -- evm-lab gap analysis mentions hackathons, CI, low-RAM users |
| OS/hardware support matrix for Solo | **Partially documented** -- CI docs say 6 CPU/12GB, supports Darwin/Linux/Win32 |
| Alternatives for devs who can't run k8s | **Not documented** -- no "remote cluster" or "lite mode" guidance |
| Debugging/troubleshooting changes | **Partially documented** -- `deployment diagnostics` exists but no migration guide for Local Node debugging workflows |
| Solo release parity with public networks | **Not documented** -- no published cadence or matrix |
| Conversion tool from Local Node to Solo | **Does not exist** -- different architectures make config conversion non-trivial |
| Compatibility mode (ports/accounts/URLs) | **Partially achieved** -- Solo uses same ports (7546, 50211) and chain ID (298) by default, but account IDs differ |

#### Proposed GitHub Issues

| Issue | Description |
|-------|-------------|
| **`solo-migration-guide`** | Publish a "Migrating from Local Node to Solo" guide covering: command mapping (hedera start -> solo one-shot), port compatibility, account ID differences, config file translation, CI workflow conversion examples. |
| **`solo-remote-cluster-mode`** | Document and support connecting Solo to a remote Kubernetes cluster (cloud-hosted) for developers who can't run Docker/Kind locally. This addresses Windows, low-RAM, and enterprise firewall constraints. |
| **`solo-lite-mode`** | Investigate feasibility of a docker-compose-based "lite" mode that provides consensus + relay without Kubernetes, targeting the Local Node user segment that values simplicity over production parity. |
| **`solo-compat-mode`** | Add a `--local-node-compat` flag that configures Solo to use the same default account IDs, ports, and URLs as Local Node, minimizing migration friction for existing test suites. |
| **`solo-migration-status-tracker`** | Create a public tracking issue or project board showing migration status of all Hedera repos from Local Node to Solo, with owners and timelines. The evm-lab CSV could be the seed data. |
| **`solo-minimum-spec-matrix`** | Publish official minimum specs per deployment mode: (a) consensus-only: 4CPU/8GB, (b) consensus+relay: 4CPU/10GB, (c) full stack: 6CPU/12GB, (d) full stack + block node: 8CPU/16GB. These need to be validated through testing. |
| **`solo-windows-guidance`** | Document Windows support status: WSL2 requirements, Docker Desktop config, known limitations, tested configurations. |

---

## Current Best-Practices Guide

These are practical workflows teams can follow **right now**, before any GitHub
issues are resolved.

### Startup Optimization

**Don't rebuild the cluster for every test run.** The single biggest optimization is
reusing the Kind cluster:

```bash
# First run: full startup (~10 min)
./scripts/start-solo.sh

# Subsequent test runs: just run tests against the existing network
npx hardhat test --network solo
forge test --fork-url http://127.0.0.1:7546

# Only stop when truly done
./scripts/stop-solo.sh
```

**Pre-pull images** before first deploy:

```bash
# Pull the heaviest images into Kind ahead of time
docker pull hashgraph/full-stack-testing/ubi8-init-java21:0.59.0
kind load docker-image <image> -n solo
```

**Reduce wait tolerances** for faster failure detection in CI:

```bash
export PODS_RUNNING_MAX_ATTEMPTS=300    # 5 min instead of 15 min
export RELAY_PODS_RUNNING_MAX_ATTEMPTS=300
export PODS_READY_MAX_ATTEMPTS=120
export NETWORK_NODE_ACTIVE_MAX_ATTEMPTS=120
```

### Minimal Stack for EVM Testing

**Option A: Use `--minimal-setup`** (skips explorer and relay, then add relay back):

```bash
solo one-shot single deploy --minimal-setup
# Then manually add relay only:
solo relay deploy --deployment <name> --node-aliases node1
```

**Option B: Step-by-step for maximum control:**

```bash
# Cluster
kind create cluster -n solo
solo cluster setup --cluster-ref solo
solo deployment config create --namespace solo --deployment solo-deployment
solo deployment cluster attach --deployment solo-deployment --cluster-ref solo

# Consensus only
solo keys consensus generate --deployment solo-deployment --gossip-keys --tls-keys
solo consensus network deploy --deployment solo-deployment
solo consensus node setup --deployment solo-deployment
solo consensus node start --deployment solo-deployment

# Add only what you need:
solo mirror deploy --deployment solo-deployment   # if you need mirror
solo relay deploy --deployment solo-deployment    # if you need JSON-RPC
# Skip explorer, block node, MinIO if not needed
```

### Account Setup

**Use the pre-created accounts.** One-shot creates 30 accounts automatically. The
ECDSA-alias ones are at `0.0.1002`+ with 10,000 HBAR. To find their keys after the
terminal has scrolled:

```bash
# Get a specific account's info including private key
solo ledger account info --account-id 0.0.1002 --deployment solo-deployment --private-key
```

**Create high-balance accounts for integration testing:**

```bash
solo ledger account create \
  --deployment solo-deployment \
  --hbar-amount 1000000 \
  --generate-ecdsa-key \
  --set-alias
```

### Port Forwarding Recovery

If port forwards die after one-shot finishes:

```bash
# Re-establish gRPC proxy
kubectl port-forward -n solo svc/haproxy-node1-svc 50211:50211 &

# Re-establish mirror REST
kubectl port-forward -n solo svc/mirror-rest 8081:80 &

# Re-establish mirror gRPC
kubectl port-forward -n solo svc/mirror-grpc 5600:5600 &

# Re-establish relay
kubectl port-forward -n solo svc/relay-node1-hedera-json-rpc-relay 7546:7546 &
```

Wrap this in a reusable script. The evm-lab's `start-solo.sh` already health-checks
the relay after deployment.

### CI Workflow

**Use larger runners and pin the Solo version:**

```yaml
jobs:
  test:
    runs-on: ubuntu-latest  # Need 6+ CPU; check runner specs
    steps:
      - uses: actions/checkout@v4

      # Option A: Use the official action (recommended)
      - uses: hiero-ledger/hiero-solo-action@main
        with:
          solo-version: '0.53.0'

      # Option B: Manual setup
      - name: Setup Kind
        uses: helm/kind-action@v1
        with:
          cluster_name: solo
          node_image: kindest/node:v1.31.4

      - name: Install Solo
        run: npm install -g @hashgraph/solo@0.53.0

      - name: Deploy
        run: solo one-shot single deploy --quiet
        timeout-minutes: 20
        env:
          PODS_RUNNING_MAX_ATTEMPTS: 300
          RELAY_PODS_RUNNING_MAX_ATTEMPTS: 300

      - name: Run Tests
        run: npx hardhat test --network solo
        timeout-minutes: 10
```

**Resource requirements by runner type:**

| Runner | CPU | Memory | Sufficient? |
|--------|-----|--------|-------------|
| `ubuntu-latest` (GitHub-hosted) | 2 | 7 GB | **No** -- well below 6 CPU / 12 GB minimum |
| `ubuntu-latest-8-cores` | 8 | 32 GB | Yes -- adequate for full stack |
| Self-hosted (6+ CPU, 12+ GB) | varies | varies | Check Docker allocation |

### Log Streaming Without kubectl Expertise

Until `solo logs` exists, use these kubectl commands:

```bash
# JSON-RPC Relay logs (most common for EVM debugging)
kubectl logs -n solo -l app=hedera-json-rpc-relay -f --tail=100

# Mirror Node importer logs (for sync issues)
kubectl logs -n solo -l app.kubernetes.io/component=importer -f --tail=100

# Consensus node logs
kubectl logs -n solo -l app=network-node -c root-container -f --tail=100

# All pods status at a glance
kubectl get pods -n solo -o wide
```

### Deployment Name Management

Until env var support is added to the `--deployment` flag:

```bash
# Set a shell alias for your session
export SOLO_DEPLOY="solo-deployment"
alias solod='solo --deployment $SOLO_DEPLOY'

# Then use:
solod ledger account create --hbar-amount 1000 --generate-ecdsa-key
solod deployment diagnostics connections

# Or read from the cached one-shot name:
SOLO_DEPLOY=$(cat ~/.solo/cache/last-one-shot-deployment.txt 2>/dev/null)
```

### Version Checking

```bash
# Solo CLI version
solo --version

# Check deployed component versions via Helm
helm list -n solo
# Shows chart versions for solo-deployment, mirror, relay, explorer

# Check specific image versions running in pods
kubectl get pods -n solo \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'
```

### Test Configuration for Solo

Hardhat config (`hardhat.config.ts`):

```typescript
solo: {
  url: "http://127.0.0.1:7546",
  chainId: 298,
  timeout: 120_000,  // 2 min for k8s overhead
  accounts: [
    "0x<private-key-from-solo-output>"
  ]
}
```

Test helpers -- the critical difference from local Ethereum:

```typescript
// After state-changing transactions, wait for mirror node sync
async function waitForMirrorSync(ms = 2500) {
  await new Promise(r => setTimeout(r, ms));
}

// Usage after deploy or state change:
const tx = await contract.someMethod();
await tx.wait();
await waitForMirrorSync(); // Critical on Solo -- mirror node ingestion pipeline
```

**Timing configuration reference:**

| Parameter | Local Node | Solo | Notes |
|-----------|-----------|------|-------|
| Network timeout (hardhat config) | 60,000ms | 120,000ms | Kubernetes overhead |
| Post-transaction wait | 500ms | 2,500ms | Mirror Node sync |
| Intermediate wait between TXs | 300ms | 1,500ms | Between sequential TXs |
| Mocha/Jest test timeout | 40,000ms | 90,000ms | Allow network latency |
| Startup time | 57.5s | 711.5s | 12.3x difference |

---

## Proposed GitHub Issues

### High Priority Issues

These block adoption and have the highest impact-to-effort ratio.

---

#### 1. `solo-deployment-env-var`

**Title:** Support `SOLO_DEPLOYMENT` environment variable as default for `--deployment` flag

**Labels:** `enhancement`, `developer-experience`, `good-first-issue`

**Description:**

Currently, the `--deployment` flag in `src/commands/flags.ts:1947` has a
`defaultValue` of empty string `''` and no environment variable fallback. Users must
pass `--deployment <name>` on every command invocation.

Solo's `EnvironmentStorageBackend` supports `SOLO_DEPLOYMENTS_0_NAME` for internal
config, but this format is unintuitive and undocumented for CLI users.

**Acceptance Criteria:**

1. The `--deployment` flag reads from `SOLO_DEPLOYMENT` env var when no explicit
   `--deployment` is passed
2. Fallback order: explicit flag > `SOLO_DEPLOYMENT` env var >
   last-one-shot cached name (`~/.solo/cache/last-one-shot-deployment.txt`) >
   prompt user
3. Update `env.md` documentation
4. Add integration test verifying env var is respected

**Affected code:**
- `src/commands/flags.ts:1947-1969` -- Add env var support to deployment flag definition
- `docs/site/content/en/docs/env.md` -- Document `SOLO_DEPLOYMENT`

---

#### 2. `solo-port-forward-persistence`

**Title:** Port forwards (especially gRPC 50211) terminate after one-shot command exits

**Labels:** `bug`, `reliability`, `one-shot`

**Description:**

After `solo one-shot single deploy` completes, port forwards for gRPC proxy (50211),
mirror REST, and other services terminate or become unreliable. Users report needing
manual `kubectl port-forward` commands to restore connectivity.

The persistent port-forward script
(`src/integration/kube/k8-client/resources/pod/persist-port-forward.ts`) is designed
to auto-reconnect, but it appears to be terminated when the parent Solo CLI process
exits.

**Acceptance Criteria:**

1. All port forwards established during one-shot survive CLI process exit
2. Port-forward processes are daemonized or spawned independently
3. PID files written to `~/.solo/port-forwards/` for lifecycle management
4. `solo deployment port-forward --deployment <name>` command re-establishes all
   port forwards
5. `solo deployment status` shows active port forward health

**Investigation needed:**
- How are port-forward child processes managed in the one-shot lifecycle?
- Is `persist-port-forward.ts` invoked as a detached process or a child of the CLI?
- What happens on macOS vs Linux when the parent process exits?

---

#### 3. `solo-fast-exit`

**Title:** 30-60 second delay after command completion before shell prompt returns

**Labels:** `bug`, `performance`, `developer-experience`

**Description:**

After running `solo ledger account create` (or similar commands), there is a
30-60 second delay between the action completing and control returning to the shell.
The account is created and funded successfully, but cleanup/shutdown takes
disproportionately long.

**Likely root causes:**

1. `NODE_CLIENT_PING_INTERVAL` (30000ms) -- SDK client may wait for an in-flight
   ping cycle to complete before closing
2. `SOLO_LEASE_DURATION` (20s) -- Distributed lock may wait for full lease duration
   before releasing
3. SDK client `close()` may perform graceful shutdown with long timeout
4. `NODE_CLIENT_REQUEST_TIMEOUT` (600000ms) may affect shutdown behavior

**Acceptance Criteria:**

1. Commands return to shell within 3 seconds of completing their primary action
2. SDK client close is non-blocking with a 3-second hard timeout
3. Lease release is immediate (best-effort, not blocking)
4. Add `SOLO_CLIENT_SHUTDOWN_TIMEOUT` env var (default: 3000ms)

---

#### 4. `solo-start-stop`

**Title:** Add `solo start` and `solo stop` as simplified entry points

**Labels:** `enhancement`, `developer-experience`, `documentation`

**Description:**

New users should be able to type `solo start` to launch a local Hedera network and
`solo stop` to tear it down, without knowing about one-shot modes, deployment names,
or Kubernetes. This is the Hardhat/Foundry-equivalent experience.

**Acceptance Criteria:**

1. `solo start` is an alias for `solo one-shot single deploy --quiet` with a
   deterministic deployment name (`solo-deployment`)
2. `solo stop` is an alias for `solo one-shot single destroy` that reads the cached
   deployment name
3. After `solo start`, a clean summary block is printed:

```
Hedera Solo Network Running

JSON-RPC (EVM):   http://127.0.0.1:7546
Mirror REST API:  http://localhost:8081/api/v1
gRPC (SDK):       localhost:50211
Explorer:         http://localhost:8080
Chain ID:         298 (0x12a)
Deployment:       solo-deployment

Accounts (ECDSA with EVM alias, 10,000 HBAR each):
  0.0.1002  0x<key>
  0.0.1003  0x<key>
  ...
```

4. `solo start --minimal` deploys consensus + relay only
5. `solo start --version <tag>` sets the consensus node version

---

#### 5. `solo-ci-resource-matrix`

**Title:** Publish official resource requirements by deployment mode and CI runner recommendations

**Labels:** `documentation`, `ci-cd`

**Description:**

CI users are deploying Solo on runners that don't meet minimum specs, causing relay
pod failures and timeouts. The current docs state "6 CPU / 12 GB" but don't
differentiate by deployment mode or recommend specific GitHub Actions runner types.

**Acceptance Criteria:**

1. Publish tested resource requirements in `solo-ci-workflow.md`:

| Mode | CPU | Memory | GH Actions Runner |
|------|-----|--------|-------------------|
| Consensus only | 4 | 8 GB | `ubuntu-latest` (marginal) |
| Consensus + Relay | 4 | 10 GB | 4-core runner |
| Full stack (one-shot) | 6 | 12 GB | 8-core runner |
| Full + Block Node | 8 | 16 GB | 16-core runner |

2. Provide a tested GitHub Actions workflow example using `hiero-solo-action`
3. Document timeout env var presets for CI (tighter than defaults for faster failure)
4. Test and validate on actual GitHub-hosted runners

---

#### 6. `solo-logs-command`

**Title:** Add `solo logs <component>` command for streaming service logs

**Labels:** `enhancement`, `developer-experience`, `debugging`

**Description:**

Developers debugging EVM test failures need to inspect JSON-RPC relay and mirror
node importer logs. Currently this requires knowing kubectl pod label selectors and
container names.

**Acceptance Criteria:**

1. `solo logs relay --deployment <name>` streams relay pod logs
2. `solo logs mirror --deployment <name>` streams mirror importer logs
3. `solo logs consensus --deployment <name>` streams consensus node logs
4. `solo logs explorer --deployment <name>` streams explorer logs
5. `--follow` flag enables live streaming (`kubectl logs -f`)
6. `--tail N` flag shows last N lines (default: 100)
7. `--all` flag multiplexes all component logs with prefixed output
8. Component names map internally to the correct Kubernetes label selectors and
   container names

---

### Medium Priority Issues

These improve adoption quality and developer experience.

---

#### 7. `solo-evm-mode`

**Title:** Add `--evm-only` mode to one-shot that deploys consensus + relay without mirror/explorer

**Labels:** `enhancement`, `evm`, `performance`

**Description:**

EVM testing teams only need `eth_sendRawTransaction` and `eth_call` via the JSON-RPC
relay. Mirror node, explorer, and block node are unnecessary overhead. A
`--evm-only` flag would deploy consensus node + relay only, reducing memory footprint
and startup time.

**Technical consideration:** The relay currently queries mirror node for some
operations (transaction history, gas estimation). An EVM-only mode would either need
to (a) accept that only real-time operations work, or (b) configure the relay with a
lightweight in-memory fallback for mirror-dependent queries.

---

#### 8. `solo-predefined-balance-flag`

**Title:** Add `--predefined-account-balance` flag to configure initial account funding

**Labels:** `enhancement`, `accounts`, `good-first-issue`

**Description:**

The default 10,000 HBAR per predefined account (`predefined-accounts.ts:26`) is
insufficient for heavy integration testing. Add a flag to one-shot commands:

```bash
solo one-shot single deploy --predefined-account-balance 1000000
```

**Affected code:**
- `src/commands/one-shot/predefined-accounts.ts:26` -- Replace hardcoded
  `Hbar.from(10_000, HbarUnit.Hbar)` with a configurable parameter
- `src/commands/flags.ts` -- Add new flag definition
- `src/commands/one-shot/default-one-shot.ts` -- Thread the flag through to
  account creation

---

#### 9. `solo-architecture-diagram`

**Title:** Add architecture diagrams and plain-language prerequisite explanations to documentation

**Labels:** `documentation`, `onboarding`

**Description:**

JS/TS developers without DevOps backgrounds need:

1. A diagram showing: Host OS -> Docker -> Kind cluster -> Pods (consensus, mirror,
   relay, explorer)
2. A "Why These Prerequisites?" page explaining Docker, Kind, kubectl, Helm in
   simple terms
3. A glossary differentiating: Kubernetes node vs Hedera consensus node, Kubernetes
   deployment vs Solo deployment, pod vs service
4. A data flow diagram: Client -> Relay (7546) -> Consensus Node -> Record Stream ->
   Mirror Importer -> DB -> Mirror REST (8081) -> Explorer (8080)

---

#### 10. `solo-migration-guide`

**Title:** Publish "Migrating from Local Node to Solo" guide

**Labels:** `documentation`, `migration`, `local-node`

**Description:**

With Local Node being deprecated, teams need a migration guide covering:

1. Command mapping: `hedera start` -> `solo one-shot single deploy`
2. Port compatibility (both use 7546, 50211 by default)
3. Account ID differences
4. CI workflow conversion examples (`npx hedera` -> solo CLI or `hiero-solo-action`)
5. Test configuration changes (timeout increases, mirror sync delays)
6. The 21+ repos in `local-node-migration-status.csv` that still need conversion

---

#### 11. `solo-relay-readiness-diagnostics`

**Title:** Auto-dump relay pod logs and events on readiness timeout

**Labels:** `enhancement`, `debugging`, `ci-cd`

**Description:**

When the relay pod fails to become ready (common in CI), Solo silently waits for the
full timeout before failing. Instead, Solo should:

1. Detect that a pod has been pending/CrashLoopBackOff for >60s
2. Automatically dump pod events (`kubectl describe pod`)
3. Dump last 50 lines of pod logs
4. Print a clear message: "Relay pod failed to start. Common causes: insufficient
   memory, mirror node not ready. See logs above."

---

#### 12. `solo-version-info`

**Title:** Add `solo version --components` to display all deployed component versions

**Labels:** `enhancement`, `developer-experience`

**Description:**

Users need to see what versions are actually running in their deployment. Currently
`solo --version` only shows the CLI version. Add:

```bash
solo version --components --deployment solo-deployment
```

Output:
```
Solo CLI:        0.53.0
Consensus Node:  v0.67.2
Mirror Node:     v0.145.2
JSON-RPC Relay:  v0.73.0
Explorer:        v25.1.1
Block Node:      (not deployed)
Solo Charts:     v0.59.0
```

This should query the actual running pod images, not just the configured defaults.

---

#### 13. `solo-display-accounts-command`

**Title:** Add command to re-display pre-funded account info for a running deployment

**Labels:** `enhancement`, `accounts`, `developer-experience`

**Description:**

After one-shot completes, the 30 pre-funded accounts and their private keys scroll
past in terminal output and are lost. Add:

```bash
solo deployment accounts --deployment solo-deployment
```

Output:
```
Pre-funded Accounts (ECDSA with EVM alias):
  Account ID    EVM Address                                  Private Key                     Balance
  0.0.1002      0xabcd...1234                                0x3456...7890                   10,000 HBAR
  0.0.1003      0xabcd...5678                                0x3456...abcd                   10,000 HBAR
  ...
```

---

### Lower Priority Issues

These are important but represent larger efforts or affect fewer users.

---

#### 14. `solo-fast-restart`

**Title:** Implement warm restart mode that resets consensus state without recreating cluster

**Labels:** `enhancement`, `performance`

**Description:**

For test suites that need a clean network state between runs, implement a fast reset
that preserves the Kind cluster and Helm releases but wipes consensus state and
re-initializes accounts. Target: <60s restart.

---

#### 15. `solo-upgrade-latest`

**Title:** Support versionless upgrade commands that auto-detect latest compatible version

**Labels:** `enhancement`, `version-management`

**Description:**

When no version is specified on upgrade commands, fetch the latest compatible version
from a published compatibility manifest (could be a JSON file in the Solo repo or OCI
registry). Warn if the upgrade crosses a major version boundary.

---

#### 16. `solo-compatibility-matrix`

**Title:** Publish Solo version <-> component version <-> public network version matrix

**Labels:** `documentation`, `version-management`

**Description:**

Publish and maintain a compatibility matrix that maps:
- Solo CLI version -> default component versions
- Component versions -> public network compatibility (mainnet, testnet, previewnet)

This should be in the docs site and machine-readable (JSON).

---

#### 17. `solo-lite-mode`

**Title:** Investigate docker-compose-based "lite" mode without Kubernetes

**Labels:** `enhancement`, `exploration`, `large-effort`

**Description:**

For the Local Node user segment that values simplicity over production parity,
investigate feasibility of a docker-compose-based deployment mode that provides
consensus + relay without requiring Kubernetes, Kind, or Helm. This addresses the
gap for developers who can't or won't run Kubernetes locally.

---

#### 18. `solo-remote-cluster-mode`

**Title:** Document and support connecting Solo to remote Kubernetes clusters

**Labels:** `documentation`, `enhancement`

**Description:**

Document and support connecting Solo to a remote Kubernetes cluster (cloud-hosted)
for developers who can't run Docker/Kind locally. This addresses Windows, low-RAM,
and enterprise firewall constraints. Include:

- EKS, GKE, AKS cluster configuration
- Network requirements for port forwarding
- Cost estimates for running Solo in cloud k8s
- Security considerations

---

#### 19. `solo-compat-mode`

**Title:** Add `--local-node-compat` flag to preserve Local Node ports/account IDs/URLs

**Labels:** `enhancement`, `migration`, `local-node`

**Description:**

Add a `--local-node-compat` flag that configures Solo to use the same default account
IDs, ports, and URLs as Local Node, minimizing migration friction for existing test
suites.

---

#### 20. `solo-image-preload`

**Title:** Add `solo cluster preload` command to pre-pull images into Kind cluster

**Labels:** `enhancement`, `performance`

**Description:**

Add a command that pulls all required Docker images into the Kind cluster ahead of
deployment, removing image pull time from the critical path:

```bash
solo cluster preload --cluster-ref solo
```

This identifies all images needed for the configured deployment mode and runs
`kind load docker-image` for each.

---

#### 21. `solo-timeout-presets`

**Title:** Add `--timeout-profile` flag with CI/fast/patient presets

**Labels:** `enhancement`, `ci-cd`, `developer-experience`

**Description:**

Instead of requiring users to set 10+ individual timeout env vars, add:

```bash
solo one-shot single deploy --timeout-profile fast
```

Presets:
- `fast`: Tight timeouts for rapid failure detection (CI with known-good resources)
- `normal`: Current defaults
- `patient`: Extended timeouts for slow environments

---

#### 22. `solo-context-command`

**Title:** Add `solo context set` for persisting default deployment and cluster

**Labels:** `enhancement`, `developer-experience`

**Description:**

Similar to `kubectl config use-context`, add:

```bash
solo context set --deployment solo-deployment
solo context show
```

All subsequent commands would use the persisted deployment without `--deployment`.

---

#### 23. `solo-prereq-installer`

**Title:** Add `solo doctor` command to check and install prerequisites

**Labels:** `enhancement`, `onboarding`

**Description:**

Add a `solo doctor` command that checks for Docker, Kind, kubectl, Helm, and Node.js,
reports versions and compatibility, and offers to install missing dependencies via
Homebrew (macOS) or apt (Linux).

The evm-lab already has `scripts/doctor.sh` that implements this check pattern and
could serve as a reference implementation.

---

#### 24. `solo-windows-guidance`

**Title:** Document Windows support status and WSL2 requirements

**Labels:** `documentation`, `platform-support`

**Description:**

Document Windows support status: WSL2 requirements, Docker Desktop configuration,
known limitations, and tested configurations. Many enterprise developers are on
Windows and need clear guidance on whether and how Solo works in their environment.

---

## Summary Matrix

| # | User Question | Existing Feature | Best Practice Today | Proposed Issue(s) |
|---|---|---|---|---|
| 1 | Startup time 10+ min | Reuse cluster across test runs | Don't destroy/recreate per test suite | `solo-fast-restart`, `solo-image-preload` |
| 2 | Disable unused services | `--minimal-setup`, step-by-step commands | Use step-by-step deploy, add only needed components | `solo-evm-mode`, `solo-minimal-redesign` |
| 3 | Large initial balances + EVM accounts | 30 pre-funded accounts (10K HBAR), ECDSA-alias | Use predefined accounts; `ledger account create --hbar-amount 1000000` | `solo-predefined-balance-flag`, `solo-display-accounts-command` |
| 4 | gRPC proxy / mirror endpoints broken | `--force-port-forward` (default: true), `persist-port-forward.ts` | Manual kubectl port-forward if they die | `solo-port-forward-persistence`, `solo-port-forward-reconnect` |
| 5 | Falcon on GH Actions timeout | `hiero-solo-action`, timeout env vars | Use larger runners, pin version, reduce timeout env vars | `solo-ci-resource-matrix`, `solo-relay-readiness-diagnostics` |
| 6 | Simple as Hardhat/Foundry | `one-shot single deploy` does full stack | Use evm-lab's `start-solo.sh` wrapper | `solo-start-stop`, `solo-clean-output`, `solo-prereq-installer` |
| 7 | CLI env vars / SOLO_DEPLOYMENT | `SOLO_DEPLOYMENTS_0_NAME` (undocumented), cached deployment name | Shell alias + explicit `--deployment` flag | `solo-deployment-env-var`, `solo-default-deployment`, `solo-context-command` |
| 8 | Log streaming | `deployment diagnostics logs` (batch only) | kubectl logs with label selectors | `solo-logs-command` |
| 9 | Version management | `solo --version`, env var version overrides | `helm list -n solo` for deployed versions | `solo-version-info`, `solo-upgrade-latest`, `solo-compatibility-matrix` |
| 10 | Architecture docs | evm-lab gap analysis, quickstart guide | Share evm-lab docs with teams | `solo-architecture-diagram`, `solo-glossary`, `solo-prereq-explainer` |
| 11 | Post-command lag | N/A (bug) | N/A (no workaround) | `solo-fast-exit` |
| 12 | Local Node migration questions | Migration CSV, gap analysis | Share evm-lab analysis; use `hiero-solo-action` for CI repos | `solo-migration-guide`, `solo-lite-mode`, `solo-compat-mode`, `solo-minimum-spec-matrix` |

---

## Migration Status

Current state of Hedera repos migrating from `hedera-local` npm to Solo
(from `local-node-migration-status.csv`):

### Converted (4 repos)

| Repo | Workflow | Approach |
|------|----------|----------|
| hiero-block-node | `solo-e2e-test.yml` | Solo CLI with full network deployment |
| hiero-sdk-js | `build.yml` | `hiero-ledger/hiero-solo-action` GitHub Action |
| hiero-sdk-rust | `flow-rust-ci.yaml` | `hiero-ledger/hiero-solo-action` GitHub Action |
| hedera-transaction-tool | `test-contracts.yaml` | `solo one-shot single deploy` |

### Not Converted (21+ workflows across 8 repos)

| Repo | Workflows | Current Approach |
|------|-----------|------------------|
| hiero-json-rpc-relay | 6 workflows | `npm install @hashgraph/hedera-local -g` + `npx hedera` |
| hedera-smart-contracts | 4 workflows + `package.json` | `npx hedera start/stop` with docker-compose |
| stablecoin-studio | `test-contracts.yaml` | `hedera start --detached` |
| hedera-forking | `test.yml` + `package.json` | `npx hedera start/stop` |
| hedera-cli | `zxc-compile-code.yaml` | `npm install -g @hashgraph/hedera-local` |
| hedera-sourcify | `package.json` | `@hashgraph/hedera-local ^2.25.0` |

### Ineligible

| Repo | Reason |
|------|--------|
| hethers.js | Archived/inactive, uses very old hedera-local-node v1.1.0 |

---

## Priority Ranking

**High Priority (blocks adoption):**

1. `solo-deployment-env-var` -- #1 ergonomic fix, simple to implement
2. `solo-port-forward-persistence` -- broken core functionality
3. `solo-fast-exit` -- 30-60s lag is unacceptable UX
4. `solo-start-stop` -- entry point simplicity
5. `solo-ci-resource-matrix` -- unblocks CI adoption
6. `solo-logs-command` -- basic debugging capability

**Medium Priority (improves adoption):**

7. `solo-evm-mode` -- serve the largest user segment (EVM developers)
8. `solo-predefined-balance-flag` -- simple flag addition
9. `solo-architecture-diagram` -- onboarding for non-k8s developers
10. `solo-migration-guide` -- critical for Local Node sunset
11. `solo-relay-readiness-diagnostics` -- CI failure debugging
12. `solo-version-info` -- component version visibility
13. `solo-display-accounts-command` -- lost terminal output recovery

**Lower Priority (nice to have):**

14. `solo-fast-restart` -- warm restart mode
15. `solo-upgrade-latest` -- auto-detect latest compatible version
16. `solo-compatibility-matrix` -- version mapping
17. `solo-lite-mode` -- docker-compose alternative (large effort)
18. `solo-remote-cluster-mode` -- cloud cluster support
19. `solo-compat-mode` -- Local Node port/account compatibility
20. `solo-image-preload` -- pre-pull optimization
21. `solo-timeout-presets` -- CI timeout profiles
22. `solo-context-command` -- persistent defaults
23. `solo-prereq-installer` -- `solo doctor` command
24. `solo-windows-guidance` -- Windows platform docs
