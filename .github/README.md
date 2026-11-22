# Gitea Actions — CI Runner Setup

CI runs the same quality gate as the agents, `tools/verify.sh all --all-files`,
inside the same toolbox image
([tools/container/Containerfile](../tools/container/Containerfile)). The
workflow is [workflows/ci.yml](workflows/ci.yml).

## Runner Requirements

A Gitea `act_runner` registered with the `self-hosted` label, running jobs in
**host mode** (the label maps to `host`, not to a `docker://` image), with:

| Tool | Purpose |
| --- | --- |
| `podman` (or `docker`) | Builds the toolbox image and runs the checks in it |
| `git`, `bash`, `python3` | Checkout and the failure-detail step (`tools/log.sh`) |

Using Docker instead of Podman: set `CONTAINER_ENGINE: docker` in the
workflow's `env`. The `:Z` volume flag relabels the checkout for SELinux;
drop it if the runner host has no SELinux.

Nothing else is installed on the runner: PlatformIO, compilers, linters and
OpenSpec all come from the image. PlatformIO toolchains are cached in the
`obsidian-pio` volume, so only the first run downloads them.

## What Runs on Every Push / PR to `main`

| Step | Fails when |
| --- | --- |
| Build toolbox image | the Containerfile doesn't build |
| `tools/verify.sh all --all-files` | any of docs, specs, format, rules, lint, build or test fails, or the ATmega exceeds its size budget |
| Show failing step details | (only on failure) prints the first errors of each failed step |

Boards without a `platformio.ini` yet are skipped, not failed.

## Troubleshooting

- **"No runner available for label self-hosted"**: start the runner and
  check its labels.
- **`podman: command not found`**: install Podman on the runner host or
  switch `CONTAINER_ENGINE` to `docker`.
- **Permission denied on `/work`**: SELinux relabeling; keep `:Z` on the
  volume, or run the runner as a user that owns the checkout.
