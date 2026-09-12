# precommit-security-hooks

A ready-to-run `pre-commit` bundle that blocks secrets, bad Dockerfiles, insecure IaC
and unsafe GitHub Actions workflows **before** they reach your repository.

Every scanner runs from its **official, version-pinned container image**. Nothing is
installed on a developer's machine, added to `PATH`, or written to a shell profile.
A teammate needs exactly two things: Docker and a hook runner.

```sh
git clone https://github.com/moheedinamdar/precommit-security-hooks.git ~/tools/precommit-security-hooks
cd /path/to/your/repo
~/tools/precommit-security-hooks/install.sh --profile core
```

---

## Contents

- [Why container images](#why-container-images)
- [Requirements](#requirements)
- [Install](#install)
- [Profiles](#profiles)
- [Hook reference](#hook-reference)
- [Configuration files](#configuration-files)
- [The secrets baseline](#the-secrets-baseline)
- [Scripts](#scripts)
- [Editing the hook set](#editing-the-hook-set)
- [Keeping pins current](#keeping-pins-current)
- [Running the same checks in CI](#running-the-same-checks-in-ci)
- [Troubleshooting](#troubleshooting)
- [Design decisions](#design-decisions)
- [Repository layout](#repository-layout)

---

## Why container images

The usual way to ship a security hook bundle is `language: golang` / `language: python`
hooks that compile or `pip install` a scanner into a per-repo cache. That means every
developer builds a toolchain, versions drift between laptops and CI, and "works on my
machine" becomes a security problem rather than a style one.

This bundle uses pre-commit's `docker_image` language instead:

| | Toolchain hooks | This bundle |
| --- | --- | --- |
| Installed on the machine | Go, Python, Node, each scanner | Docker + a hook runner |
| Version drift across the team | per-laptop | impossible — the image tag is the version |
| Onboarding | install N tools | `docker pull` on first run |
| Removal | hunt down binaries | `docker image rm` |

The one exception is the repository-hygiene block, which uses the upstream
[`pre-commit/pre-commit-hooks`](https://github.com/pre-commit/pre-commit-hooks) repo.
Those are pure-Python and the runner builds them an isolated cached environment —
still nothing on `PATH`. Under `prek` most of them execute as native Rust with no
environment at all.

## Requirements

| | Why | Install |
| --- | --- | --- |
| **Docker** | every scanner is a container | Docker Desktop, Colima, Rancher Desktop, or Podman with a `docker` shim |
| **A hook runner** | wires the hooks into git | `curl -LsSf https://prek.j178.dev/install.sh \| sh` **or** `pipx install pre-commit` |

Either runner works — the config format is identical.
[`prek`](https://github.com/j178/prek) is a single Rust binary with no Python
dependency and is noticeably faster; `pre-commit` is the reference implementation.
`install.sh` auto-detects, preferring `prek`.

First run pulls roughly 1–2 GB of images depending on profile. After that they are cached.

## Install

```sh
cd /path/to/your/repo
/path/to/precommit-security-hooks/install.sh --profile core
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--profile core\|iac\|full` | `core` | which hook set to install |
| `--runner auto\|pre-commit\|prek` | `auto` | which runner to wire up |
| `--target DIR` | `$PWD` | repository to install into |
| `--config-only` | off | write config files but do not touch `.git/hooks` |
| `--force` | off | overwrite an existing `.pre-commit-config.yaml` |

What it does, in order:

1. Validates the profile, that the target is a git repository, and that Docker is on `PATH`.
2. Copies the chosen profile to `.pre-commit-config.yaml`.
   **Refuses to clobber an existing config** unless `--force` — it prints a `diff` command instead.
3. Copies `.gitleaks.toml`, `.gitleaksignore` and `.hadolint.yaml`, **skipping any that
   already exist** so your repo's existing tuning always wins.
4. Runs `<runner> install --install-hooks` for the `pre-commit`, `commit-msg` and
   `pre-push` hook types.

Commit the resulting config files so the rest of the team inherits the same set.

## Profiles

Profiles are cumulative: `iac` is `core` plus IaC, `full` is `iac` plus supply chain.

| | core | iac | full |
| --- | :---: | :---: | :---: |
| Secrets (gitleaks, trufflehog, detect-private-key) | ✅ | ✅ | ✅ |
| Dockerfile lint (hadolint) | ✅ | ✅ | ✅ |
| Shell analysis (shellcheck) | ✅ | ✅ | ✅ |
| Conventional Commits | ✅ | ✅ | ✅ |
| Repository hygiene (11 checks, incl. `detect-private-key`) | ✅ | ✅ | ✅ |
| Terraform fmt, Trivy, Checkov, kubeconform | — | ✅ | ✅ |
| zizmor, actionlint, osv-scanner, shfmt | — | — | ✅ |
| Hooks total | 16 | 20 | 24 |

Pick `core` unless you have a reason not to. It is the set that is fast enough that
nobody is tempted to `--no-verify`.

## Hook reference

Stage `pre-commit` runs on `git commit`; `pre-push` on `git push`; `commit-msg`
validates the message.

### Secrets — all profiles

| Hook | Image | Stage | Notes |
| --- | --- | --- | --- |
| `gitleaks` | `ghcr.io/gitleaks/gitleaks:v8.30.1` | pre-commit | Offline regex + entropy over the files being committed. |
| `trufflehog` | `trufflesecurity/trufflehog:3.97.4` | **pre-push** | Verifies whether a credential is actually live. Last 50 commits. Fails only on `verified` and `unknown` results. |
| `detect-private-key` | `pre-commit-hooks` | pre-commit | Raw PEM blocks. |

> **Privacy note.** TruffleHog verification sends candidate credentials to vendor APIs
> to test them. That is the entire point of verification, and it is why the hook runs
> on push rather than on every commit. To disable it, add `--no-verification` to the
> hook `entry` — expect considerably more noise.

### Containers, shell, commit messages — all profiles

| Hook | Image | Stage | Notes |
| --- | --- | --- | --- |
| `hadolint` | `hadolint/hadolint:v2.15.1` | pre-commit | Dockerfile lint with embedded ShellCheck. Reads `.hadolint.yaml`. |
| `shellcheck` | `koalaman/shellcheck:v0.11.0` | pre-commit | `--severity=warning`, `--external-sources`. |
| `conventional-commit` | none | commit-msg | A `pygrep` regex — no image, no interpreter. Allows merge, revert, fixup and squash messages. |

### Repository hygiene — all profiles

From `pre-commit/pre-commit-hooks` rev `v6.0.0`: `detect-private-key`,
`check-added-large-files` (`--maxkb=1024`), `check-merge-conflict`,
`check-case-conflict`, `forbid-submodules`, `check-yaml`, `check-json`, `check-toml`,
`end-of-file-fixer`, `trailing-whitespace`, `no-commit-to-branch` (`main`, `master`).

### Infrastructure as code — `iac` and `full`

| Hook | Image | Notes |
| --- | --- | --- |
| `terraform-fmt` | `hashicorp/terraform:1.16.2` | `fmt -check -diff -recursive`. |
| `trivy-config` | `aquasec/trivy:0.74.0` | Misconfiguration scanning, `HIGH,CRITICAL` only. Replaces the deprecated `tfsec`. Needs network on first run to fetch checks. |
| `checkov` | `bridgecrew/checkov:3.3.16` | Policy-as-code. `--skip-download` keeps it offline after the image pull. |
| `kubeconform` | `ghcr.io/yannh/kubeconform:v0.8.0` | Schema validation. **Scoped to `k8s/`, `kubernetes/`, `manifests/`, `deploy/`** — edit `files:` if your manifests live elsewhere. |

### CI and supply chain — `full`

| Hook | Image | Stage | Notes |
| --- | --- | --- | --- |
| `zizmor` | `ghcr.io/zizmorcore/zizmor:1.30.1` | pre-commit | Audits workflows **and `.pre-commit-config.yaml` itself** — impostor commits, unpinned or archived hook repos, insecure URL schemes. |
| `actionlint` | `rhysd/actionlint:1.7.12` | pre-commit | Workflow syntax, expression typing, runner labels. |
| `osv-scanner` | `ghcr.io/google/osv-scanner:v2.5.1` | **pre-push** | Known-vulnerable dependencies. Gated on lockfile patterns — with no package source it exits 128, which would otherwise fail every push in a repo with no dependencies. |
| `shfmt` | `mvdan/shfmt:v3.14.1` | pre-commit | `--diff --indent 2`. |

Semgrep is present but **commented out** in `profiles/parts/60-supply-chain.yaml`: a
~600 MB image and a multi-second scan is a deliberate opt-in, not a default.

## Configuration files

Installed into your repository root, where each tool auto-discovers them. No config
paths are hard-coded in the hook definitions, so the profiles work unmodified in any
repository.

| File | Consumed by | Contains |
| --- | --- | --- |
| `.gitleaks.toml` | gitleaks | `useDefault = true` plus allowlists for fixtures, lockfiles, vendored code, binary assets, and placeholder patterns such as `${VAR}`, `<your-token>`, `changeme`. |
| `.gitleaksignore` | gitleaks | Reviewed-and-accepted finding fingerprints, `<commit>:<path>:<rule-id>:<line>`. |
| `.hadolint.yaml` | hadolint | `failure-threshold: warning`, trusted registries for DL3026, and rule overrides. `DL3002`/`DL3004`/`DL3007` promoted to **error**; `DL3008`/`DL3013` (apt/pip version pinning) ignored with a stated rationale. |

## The secrets baseline

Git hooks only ever see what you are committing. An existing repository usually has
findings already in history, and a bundle that fails on all of them on day one gets
uninstalled on day one. That is what the baseline is for.

```sh
scripts/scan.sh baseline     # record today's findings as accepted
```

This writes `.gitleaks-baseline.json`, which `scan.sh secrets` then excludes.

**A baseline is an acknowledgement, not a fix.** The rules, as stated in
`.gitleaksignore`:

1. If a value was ever a real credential, **rotate it first**. It remains in git
   history no matter what any ignore file says.
2. Every entry needs a comment recording who reviewed it and why.
3. Fingerprints include the line number, so they expire when a file moves. That is
   deliberate — it forces re-review instead of silent drift.
4. Shrink the baseline over time. Never regenerate it to make a failure go away.

## Scripts

| Script | Purpose |
| --- | --- |
| `install.sh` | Install a profile into a repository (see [Install](#install)). |
| `scripts/scan.sh [secrets\|verified\|baseline\|all]` | On-demand deep scans over **full git history**, which the hooks never see. `secrets` = gitleaks; `verified` = trufflehog live-credential check; `baseline` = record current findings. Default: `all`. |
| `scripts/verify.sh` | The bundle's test suite. See below. |
| `scripts/check-updates.sh` | Compares each pinned image against the latest upstream GitHub release. Set `GITHUB_TOKEN` to raise the anonymous rate limit. |
| `scripts/build-profiles.sh [--check]` | Regenerates the profiles from `profiles/parts/`. `--check` fails on drift, for CI. |

### `scripts/verify.sh`

A scanner that silently passes is worse than no scanner, because it buys false
confidence. `verify.sh` exists to catch exactly that. It builds a throwaway git
repository, fills it with deliberately broken fixtures, and asserts **13 outcomes**:

- **10 hooks must fail**: `gitleaks`, `hadolint`, `shellcheck`, `terraform-fmt`,
  `trivy-config`, `checkov`, `kubeconform`, `zizmor`, `actionlint`, `osv-scanner`.
- **1 hook must pass**: `trufflehog` — the fixture credentials are synthetic, so
  nothing verifies as live. Passing is the correct result and proves the hook runs
  without erroring.
- **2 commit-message cases**: `add some stuff` rejected, `feat(hooks): …` accepted.

This is not theoretical. It is what caught the `gitleaks` failure documented under
[Troubleshooting](#troubleshooting) — a hook that was reporting success while
scanning nothing.

The fixtures live in `demo/`. Note `demo/leaky.env.tmpl`: its credential values are
**generated at run time**, never committed. A repository that teaches secret scanning
must not ship strings that trip secret scanners — a literal token there would trip
GitHub push protection and every downstream fork's scanners. The generated values
still match the gitleaks rule shapes, so the hook is exercised against a genuine match.

## Editing the hook set

`profiles/*.yaml` are **generated — do not edit them**. The sources are:

```text
profiles/parts/00-header.yaml         runner settings, shared preamble
profiles/parts/10-secrets.yaml        gitleaks, trufflehog
profiles/parts/20-core.yaml           hadolint, shellcheck, conventional-commit
profiles/parts/50-iac.yaml            terraform, trivy, checkov, kubeconform
profiles/parts/60-supply-chain.yaml   zizmor, actionlint, osv-scanner, shfmt
profiles/parts/90-hygiene.yaml        pre-commit-hooks
```

Edit a part, then:

```sh
scripts/build-profiles.sh    # regenerates core, iac, full and this repo's own config
scripts/verify.sh            # prove the change still detects what it claims to
```

Concatenating from shared parts is what stops the three profiles drifting apart — a
fix applied to `core` cannot silently miss `full`. `build-profiles.sh --check` enforces
it.

This repository runs the `full` profile on itself, with `exclude: ^demo/` because those
fixtures are broken on purpose.

## Keeping pins current

`pre-commit autoupdate` cannot help here: it bumps `rev:` on hook *repositories*, and
this bundle pins *images*. `scripts/check-updates.sh` is the replacement.

```text
$ scripts/check-updates.sh
IMAGE                            PINNED       LATEST       STATUS
ghcr.io/gitleaks/gitleaks        v8.30.1      v8.30.1      up to date
aquasec/trivy                    0.74.0       0.75.0       UPDATE AVAILABLE
```

To upgrade: edit the pin in `profiles/parts/*.yaml`, run `scripts/build-profiles.sh`,
then `scripts/verify.sh` to confirm the new image still behaves the same way.

## Running the same checks in CI

Hooks are a fast feedback loop, not an enforcement boundary — anyone can
`git commit --no-verify`. Run the same config in CI so a bypass cannot reach `main`:

```yaml
# .github/workflows/security-hooks.yml
name: security-hooks
on: [push, pull_request]
permissions:
  contents: read
jobs:
  hooks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0          # gitleaks and trufflehog need history
      - run: pipx install pre-commit
      - run: pre-commit run --all-files --show-diff-on-failure
```

The action is pinned to a commit SHA because `zizmor`'s `unpinned-uses` audit flags
version tags — this bundle would otherwise fail its own check.

## Troubleshooting

**`docker: Cannot connect to the Docker daemon`** — Docker is not running. Every
scanner is a container; start Docker Desktop/Colima and retry.

**The first run is very slow** — it is pulling images. Subsequent runs use the cache.
Pre-warm with `pre-commit run --all-files` immediately after install.

**gitleaks reported nothing on a file that obviously contains a secret** — the fixed
version of a real bug, worth understanding. The hook deliberately runs
`gitleaks dir`, not `gitleaks git`. Because the container runs as the host UID, git
inside the container refuses the bind-mounted repository with *"detected dubious
ownership"*, gitleaks falls back to `--no-index`, and **exits 0** — a scanner that
silently passes. Using `dir` with filenames supplied by the runner removes git from the
path entirely, and is faster. `scripts/scan.sh`, which genuinely needs history, solves
the same problem with `GIT_CONFIG_COUNT`/`safe.directory` environment variables so the
caller's git config is never modified.

**`osv-scanner` fails with exit 128** — it found no package source. The hook is gated
on lockfile patterns to avoid this; if you hit it, your lockfile sits at a path the
`files:` regex does not match.

**`kubeconform` never runs** — it is scoped to `k8s/`, `kubernetes/`, `manifests/` and
`deploy/`. Adjust `files:` in `profiles/parts/50-iac.yaml`.

**A hook is too slow on commit** — move it to `stages: [pre-push]`, as `trufflehog` and
`osv-scanner` already are.

**A finding is a false positive** — add a path or regex allowlist to `.gitleaks.toml`
if it is a class of false positive, or a reviewed fingerprint to `.gitleaksignore` if
it is a one-off. Do not disable the hook.

## Design decisions

**Docker-only, no host installs.** See [Why container images](#why-container-images).

**gitleaks *and* TruffleHog, not one or the other.** They answer different questions.
gitleaks is offline pattern matching — fast enough for every commit. TruffleHog asks
the vendor whether the credential is *live*, which is slow and network-bound, so it
runs on push. Together: cheap detection everywhere, expensive confirmation at the
boundary.

**No `detect-secrets`.** Yelp's `detect-secrets` is the usual source of the
`.secrets.baseline` pattern, but its last release was v1.5.0 in May 2024. Its baseline
concept is preserved here via the gitleaks baseline instead.

**Version pins, not floating tags.** Every image is pinned to a release tag.
`:latest` in a security tool means scan results change without you changing anything,
and a compromised upstream tag is pulled straight into every developer's commit path.
`check-updates.sh` makes upgrading an explicit, reviewable step.

**zizmor audits this bundle's own config.** Hook repositories are a supply-chain
surface like any other dependency. Since v1.29 zizmor reads `.pre-commit-config.yaml`
and flags impostor commits and archived or unpinned hook repos.

**Slow hooks are opt-in.** Semgrep stays commented out. A security bundle that adds ten
seconds to every commit gets bypassed, and a bypassed hook detects nothing.

## Repository layout

```text
.
├── install.sh                      installer
├── .pre-commit-config.yaml         generated; this repo dogfoods the full profile
├── .gitleaks.toml                  gitleaks rules and allowlists
├── .gitleaksignore                 accepted-finding fingerprints
├── .hadolint.yaml                  hadolint thresholds and overrides
├── profiles/
│   ├── core.yaml  iac.yaml  full.yaml      GENERATED
│   └── parts/                              edit these
├── scripts/
│   ├── build-profiles.sh  verify.sh
│   └── scan.sh            check-updates.sh
├── demo/                           deliberately broken fixtures for verify.sh
└── docs/hook-catalog.md            survey of the wider 2026 hook ecosystem
```

[`docs/hook-catalog.md`](docs/hook-catalog.md) catalogues the broader pre-commit
security tooling landscape as of September 2026 — including the tools this bundle
deliberately does not ship, and why.

## License

MIT — see [LICENSE](LICENSE).