---
name: local-qa
description: Run local QA in this repository. Use when asked to run formatting, linting, or pre-commit checks for gh-actions-for-devops, when verifying local QA, or whenever any file has been updated and local QA should be re-run.
---

# Local QA (format and lint)

Run the local QA script from the repository root:

```bash
./scripts/format-and-lint.sh
```

## Procedure

- Ensure the current working directory is the repository root.
- If any file has been updated during the current task, run the script to re-validate local QA.
- If no files were updated, do not run the script unless the user requests it.
- Execute the script exactly as shown above when it is required.
- Capture and summarize key output (success/failure, major warnings, and any files modified).
- If the script fails due to missing tooling, report the missing tool(s) and stop unless the user asks to install or fix them.
- Do not run additional commands unless the user requests them.
