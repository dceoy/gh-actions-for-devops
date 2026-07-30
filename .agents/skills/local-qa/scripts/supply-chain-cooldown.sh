# shellcheck shell=bash
# Source this file (do not execute it) in the same shell command as any
# uv/npm/pnpm install so the exported cooldown variables apply to that
# install. Sourcing it in an earlier, separate command has no effect,
# since exported variables do not persist across shell invocations.
COOLDOWN_DAYS=7
export UV_EXCLUDE_NEWER="${COOLDOWN_DAYS} days"
export NPM_CONFIG_MIN_RELEASE_AGE="${COOLDOWN_DAYS}"
export PNPM_CONFIG_MINIMUM_RELEASE_AGE=$((COOLDOWN_DAYS * 24 * 60))
