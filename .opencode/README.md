# PR Review Toolkit (OpenCode)

A comprehensive collection of specialized subagents for thorough pull request review, covering code comments, test coverage, error handling, type design, code quality, and code simplification.

Converted from Anthropic's [`pr-review-toolkit`](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit) Claude plugin to OpenCode-native agent and command files. OpenCode auto-discovers agents under `.opencode/agents/` and commands under `.opencode/commands/`, so no plugin manifest is needed.

## Agents

All agents are `mode: subagent` and inherit the session model unless overridden in `opencode.json`. They are invoked automatically by OpenCode when their description matches the request, or explicitly via the Task tool.

| Agent                   | Focus                                                                                                           | Color  | Can edit |
| ----------------------- | --------------------------------------------------------------------------------------------------------------- | ------ | -------- |
| `code-reviewer`         | General code review against AGENTS.md guidelines; bug detection; confidence-scored findings (only ≥80 reported) | green  | no       |
| `code-simplifier`       | Simplifies recently modified code for clarity while preserving functionality                                    | -      | yes      |
| `comment-analyzer`      | Verifies comment accuracy, completeness, and long-term maintainability (advisory only, no edits)                | green  | no       |
| `pr-test-analyzer`      | Reviews behavioral test coverage and rates critical gaps 1-10                                                   | cyan   | no       |
| `silent-failure-hunter` | Hunts silent failures, broad catches, and unjustified fallbacks in error handling                               | yellow | no       |
| `type-design-analyzer`  | Rates type design 1-10 on encapsulation, invariant expression, usefulness, and enforcement                      | pink   | no       |

The five review agents (`code-reviewer`, `comment-analyzer`, `pr-test-analyzer`, `silent-failure-hunter`, `type-design-analyzer`) carry `permission: edit: deny` in their frontmatter so they cannot modify files. `code-simplifier` is the only agent that may edit, and it is excluded from the automatic PR review path (see below).

## Automatic PR Review (read-only)

`.github/workflows/opencode-review.yml` defaults to OpenCode's built-in `plan` primary agent so the automatic PR review path is mechanically read-only, not merely prompt-only. The `plan` agent is customized in `opencode.json` with:

- `edit: deny` — blocks all file modification tools (`write`, `edit`, `apply_patch`).
- `bash` restricted to read-only inspection commands (`git status`, `git diff`, `git log`, `git show`, `gh pr view`, `gh pr diff`, `gh pr list`); every other bash command is denied.
- `task` denies `code-simplifier` (and every agent except the five review subagents), so the orchestrator cannot spawn an editing subagent.

The five review subagents additionally carry `permission: edit: deny` in their own frontmatter, enforcing their advisory nature regardless of how they are invoked.

`code-simplifier` retains full edit access for interactive/local use (e.g. `/review-pr simplify` from the TUI) but is never reached by the automatic PR review workflow because the `plan` agent's `task` permission denies it.

The comment-triggered `/opencode` bot (`.github/workflows/opencode-bot.yml`) is intentionally unaffected; it keeps `agent: null` (falling back to the `build` agent) so collaborators can still request implementation work.

## Command

### `/review-pr [aspects]`

Runs a comprehensive PR review, orchestrating the agents above. Accepts optional aspects: `comments`, `tests`, `errors`, `types`, `code`, `simplify`, or `all` (default). Add `parallel` to run all agents at once.

```bash
/review-pr                     # full review (all applicable)
/review-pr tests errors        # only test coverage and error handling
/review-pr all parallel        # all agents in parallel
```

## Usage Patterns

- **Targeted**: ask a question that matches an agent's focus ("check whether tests cover all edge cases" → `pr-test-analyzer`).
- **Comprehensive**: run `/review-pr all` before opening a PR.
- **Proactive**: OpenCode may spawn `code-reviewer` after code changes, `comment-analyzer` after docs are added, etc.

Recommended workflow:

1. Write code → `code-reviewer`
2. Fix issues → `silent-failure-hunter` (if error handling changed)
3. Add tests → `pr-test-analyzer`
4. Document → `comment-analyzer`
5. Review passes → `code-simplifier` (polish)
6. Create PR

## Adaptations from the source plugin

- Claude `plugin.json` manifest removed; OpenCode discovers files by location.
- Agent frontmatter converted to OpenCode schema (`mode: subagent`, `color` mapped to the supported OpenCode palette; `model: opus`/`inherit` dropped so the session model is inherited).
- Command frontmatter trimmed to `description`; the body keeps `$ARGUMENTS`.
- `CLAUDE.md` references changed to `AGENTS.md` (this repo's guidelines file, aliased by `CLAUDE.md`).
- Stack-specific examples from the original author's TypeScript/React project (ES modules, React Props, `errorIds.ts`, Sentry/Statsig loggers) were genericized so the agents are useful across this repo's Go codebase and other stacks.

## License & Attribution

Derived from Anthropic's `claude-plugins-official` `pr-review-toolkit`, licensed under the [Apache License 2.0](https://github.com/anthropics/claude-plugins-official/blob/main/plugins/pr-review-toolkit/LICENSE). Agent methodology and wording are preserved from the original.
