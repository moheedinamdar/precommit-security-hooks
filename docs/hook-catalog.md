# Pre-commit hook catalogue — September 2026

Every tool below can run as a `pre-commit` (or `prek`) hook today. Versions marked
**verified** were checked against the upstream release page on 2026-09-10; the rest
are stable, widely-used hooks whose exact `rev` is resolved by `pre-commit autoupdate`.

`Cost` is the rough per-commit budget on a small changeset: `fast` (<200 ms),
`medium` (0.2–2 s), `slow` (>2 s or needs the network — keep these on `pre-push`).

---

## 1. Runners

| Tool | Version | Notes |
| --- | --- | --- |
| [`pre-commit/pre-commit`](https://github.com/pre-commit/pre-commit) | **4.6.2** (verified) | The reference implementation. Python. `pre-commit hazmat` added in 4.5.0. |
| [`j178/prek`](https://github.com/j178/prek) | **0.5.2** (verified) | Rust rewrite, single static binary, no Python needed. Reads the same `.pre-commit-config.yaml`. Ships Rust-native fast paths for common `pre-commit-hooks`, workspace/monorepo mode, `prek update --cooldown-days`, and impostor-commit detection on pinned SHAs. Adopted by CPython, Airflow, FastAPI, ruff, Home Assistant. |

This bundle is authored for `pre-commit` and tested against both.

---

## 2. Secret detection

| Tool | Version | Hook ids | Cost | Notes |
| --- | --- | --- | --- | --- |
| [`gitleaks/gitleaks`](https://github.com/gitleaks/gitleaks) | **8.30.1** (verified) | `gitleaks`, `gitleaks-docker` | fast | Offline regex + entropy. Composite rules (`[[rules.required]]` with `withinLines`/`withinColumns`) since 8.28, archive scanning since 8.27, `hex`/`percent`/`b64` decoders. **Used by this bundle.** |
| [`trufflesecurity/trufflehog`](https://github.com/trufflesecurity/trufflehog) | **3.97.4** (verified) | `repo: local` (documented in upstream README) | slow | 800+ detectors that *verify* a credential is live against the vendor API. SARIF output since 3.97.0. **Used by this bundle, `pre-push` only.** |
| [`Yelp/detect-secrets`](https://github.com/Yelp/detect-secrets) | **1.5.0**, May 2024 (verified) | `detect-secrets` | fast | The original `.secrets.baseline` + `detect-secrets audit` triage workflow. **Not used here** — no release in over two years. |
| [`gitguardian/ggshield`](https://github.com/GitGuardian/ggshield) | — | `ggshield` | medium | SaaS-backed; needs an API key. |
| [`thoughtworks/talisman`](https://github.com/thoughtworks/talisman) | — | `talisman-commit` | fast | Entropy + filename heuristics. |
| `pre-commit-hooks` | 6.0.0 (verified) | `detect-private-key` | fast | Catches raw PEM blocks the regex scanners can miss. **Used by this bundle.** |

## 3. Containers

| Tool | Version | Hook ids | Cost | Notes |
| --- | --- | --- | --- | --- |
| [`hadolint/hadolint`](https://github.com/hadolint/hadolint) | **2.15.1** (verified) | `hadolint`, `hadolint-docker` | medium | Dockerfile linter with embedded ShellCheck. New in 2.15: `DL3063` reserved stage names, `DL3064` sensitive data in `ARG`/`ENV`, `DL3065` `$TARGETPLATFORM` in `FROM`, `DL3066` non-numeric UID; `DL3026` now flags `COPY --from` / mounts from untrusted registries. **Used by this bundle.** |
| [`aquasecurity/trivy`](https://github.com/aquasecurity/trivy) | — | via `terraform_trivy`, or `repo: local` | slow | Image/filesystem/config scanning. Replaces the deprecated `tfsec`. |
| [`anchore/syft`](https://github.com/anchore/syft), [`anchore/grype`](https://github.com/anchore/grype) | — | `repo: local` | slow | SBOM + vulnerability match; better suited to CI than to a commit hook. |
| [`stackrox/kube-linter`](https://github.com/stackrox/kube-linter) | — | `kube-linter` | medium | Kubernetes manifest misconfiguration. |
| [`yannh/kubeconform`](https://github.com/yannh/kubeconform) | — | `kubeconform` | fast | Schema validation for K8s manifests. |

## 4. Infrastructure as code

| Tool | Version | Hook ids | Cost | Notes |
| --- | --- | --- | --- | --- |
| [`antonbabenko/pre-commit-terraform`](https://github.com/antonbabenko/pre-commit-terraform) | **1.109.1** (verified) | `terraform_fmt`, `terraform_validate`, `terraform_tflint`, `terraform_trivy`, `terraform_docs`, `terraform_providers_lock` | medium–slow | Since 1.109.0 each wrapped tool can be pinned with `--hook-config=--tool-version=X.Y.Z` (everything except checkov). |
| [`bridgecrewio/checkov`](https://github.com/bridgecrewio/checkov) | **3.3.16** (verified) | `checkov` | slow | Policy-as-code across Terraform, CloudFormation, K8s, Helm, ARM, Dockerfile. |
| [`aws-cloudformation/cfn-lint`](https://github.com/aws-cloudformation/cfn-lint) | — | `cfn-lint` | medium | |
| [`terraform-linters/tflint`](https://github.com/terraform-linters/tflint) | — | via `terraform_tflint` | medium | |

## 5. CI / supply chain

| Tool | Version | Hook ids | Cost | Notes |
| --- | --- | --- | --- | --- |
| [`zizmorcore/zizmor`](https://github.com/zizmorcore/zizmor) | **1.30.1** (verified) | `zizmor` | medium | GitHub Actions static analysis: `template-injection`, `excessive-permissions`, `unpinned-uses`, `cache-poisoning`, `impostor-commit`, `typosquat-uses`. **Since 1.29/1.30 it also audits `.pre-commit-config.yaml` itself** — impostor commits, forbidden/archived hook repos, `insecure-url-scheme`. That makes it the one tool that secures the hook bundle as well as the workflows. |
| [`rhysd/actionlint`](https://github.com/rhysd/actionlint) | **1.7.12** (verified) | `actionlint` | fast | Workflow syntax, expression typing, runner labels, embedded ShellCheck on `run:`. |
| [`google/osv-scanner`](https://github.com/google/osv-scanner) | **2.5.1** (verified) | `osv-scanner`, Docker variant since 2.4.0 | slow | Lockfile → OSV.dev vulnerability match. |
| [`sethvargo/ratchet`](https://github.com/sethvargo/ratchet) | — | `repo: local` | fast | Pins/unpins action refs to SHAs; recognised by zizmor's version comments. |

## 6. SAST / language linters

| Tool | Version | Hook ids | Cost | Notes |
| --- | --- | --- | --- | --- |
| [`semgrep/semgrep`](https://github.com/semgrep/semgrep) | — | `semgrep` | slow | Rule-based SAST, `p/ci` and `p/secrets` registry packs. |
| [`PyCQA/bandit`](https://github.com/PyCQA/bandit) | — | `bandit` | medium | Python security linter. |
| [`astral-sh/ruff-pre-commit`](https://github.com/astral-sh/ruff-pre-commit) | **0.16.6** (verified) | `ruff-check`, `ruff-format` | fast | Rust linter/formatter; `S` ruleset re-implements most of bandit. |
| [`shellcheck-py/shellcheck-py`](https://github.com/shellcheck-py/shellcheck-py) | — | `shellcheck` | fast | Shell script analysis. **Used by this bundle.** |
| [`scop/pre-commit-shfmt`](https://github.com/scop/pre-commit-shfmt) | — | `shfmt` | fast | Shell formatter. **Used by this bundle.** |
| [`pre-commit/mirrors-mypy`](https://github.com/pre-commit/mirrors-mypy) | — | `mypy` | slow | |
| [`biomejs/pre-commit`](https://github.com/biomejs/pre-commit) | — | `biome-check` | fast | JS/TS lint + format in one Rust binary. |

## 7. Repository hygiene

| Tool | Version | Hook ids | Cost | Notes |
| --- | --- | --- | --- | --- |
| [`pre-commit/pre-commit-hooks`](https://github.com/pre-commit/pre-commit-hooks) | **6.0.0** (verified) | `detect-private-key`, `check-added-large-files`, `check-merge-conflict`, `check-case-conflict`, `forbid-submodules`, `check-executables-have-shebangs`, `check-shebang-scripts-are-executable`, `check-yaml`, `check-json`, `check-toml`, `end-of-file-fixer`, `trailing-whitespace`, `mixed-line-ending`, `no-commit-to-branch` | fast | Requires `pre-commit>=3.2.0` and Python ≥3.9. `check-byte-order-marker` and `fix-encoding-pragma` were removed in 6.0.0. **Used by this bundle.** |
| [`pre-commit/pygrep-hooks`](https://github.com/pre-commit/pygrep-hooks) | — | `python-no-eval`, `text-unicode-replacement-char` | fast | |
| [`adrienverge/yamllint`](https://github.com/adrienverge/yamllint) | — | `yamllint` | fast | **Used by this bundle.** |
| [`crate-ci/typos`](https://github.com/crate-ci/typos) | — | `typos` | fast | Faster than `codespell`. **Used by this bundle.** |
| [`codespell-project/codespell`](https://github.com/codespell-project/codespell) | — | `codespell` | fast | |
| [`DavidAnson/markdownlint-cli2`](https://github.com/DavidAnson/markdownlint-cli2) | — | `markdownlint-cli2` | fast | |
| [`python-jsonschema/check-jsonschema`](https://github.com/python-jsonschema/check-jsonschema) | — | `check-github-workflows`, `check-dependabot`, `check-renovate` | fast | |
| [`dotenv-linter/dotenv-linter`](https://github.com/dotenv-linter/dotenv-linter) | — | `dotenv-linter` | fast | |

## 8. Commit messages

| Tool | Version | Hook ids | Cost | Notes |
| --- | --- | --- | --- | --- |
| [`commitizen-tools/commitizen`](https://github.com/commitizen-tools/commitizen) | — | `commitizen`, `commitizen-branch` | fast | Conventional Commits enforcement on the `commit-msg` stage. **Used by this bundle.** |
| [`jorisroovers/gitlint`](https://github.com/jorisroovers/gitlint) | — | `gitlint` | fast | Rule-based alternative. |

---

## Deliberate exclusions

| Tool | Why not |
| --- | --- |
| `Yelp/detect-secrets` | Last release May 2024. Its `.secrets.baseline` concept is preserved here via the gitleaks baseline (see [supply-chain.md](supply-chain.md)). |
| `awslabs/git-secrets` | Unmaintained; AWS-only patterns. |
| `tfsec` | Deprecated by Aqua; folded into `trivy config` / `terraform_trivy`. |
| SaaS scanners (`ggshield`, Snyk, Semgrep AppSec Platform) | Require an account and an API token; this bundle must work on a laptop with no signup. |

## Finding more hooks

`pre-commit.com/hooks.html` is curated, not exhaustive, and rejects `language: docker`
hooks. To search the whole ecosystem, grep GitHub for the manifest file itself:

```text
path:.pre-commit-hooks.yaml language:YAML
```
