# PR Review Toolkit (OpenCode)

A comprehensive collection of specialized subagents for thorough pull request review, covering code comments, test coverage, error handling, type design, code quality, and code simplification.

Converted from Anthropic's [`pr-review-toolkit`](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit) Claude plugin to OpenCode-native agent and command files. OpenCode auto-discovers agents under `.opencode/agents/` and commands under `.opencode/commands/`, so no plugin manifest is needed.

## Agents

All agents are `mode: subagent` and inherit the session model unless overridden in `opencode.json`. They are invoked automatically by OpenCode when their description matches the request, or explicitly via the Task tool.

| Agent                   | Focus                                                                                                           | Color  |
| ----------------------- | --------------------------------------------------------------------------------------------------------------- | ------ |
| `code-reviewer`         | General code review against AGENTS.md guidelines; bug detection; confidence-scored findings (only ≥80 reported) | green  |
| `code-simplifier`       | Simplifies recently modified code for clarity while preserving functionality                                    | -      |
| `comment-analyzer`      | Verifies comment accuracy, completeness, and long-term maintainability (advisory only, no edits)                | green  |
| `pr-test-analyzer`      | Reviews behavioral test coverage and rates critical gaps 1-10                                                   | cyan   |
| `silent-failure-hunter` | Hunts silent failures, broad catches, and unjustified fallbacks in error handling                               | yellow |
| `type-design-analyzer`  | Rates type design 1-10 on encapsulation, invariant expression, usefulness, and enforcement                      | pink   |

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
