# Repository Guidelines

## Core Mandates

**CRITICAL: You must adhere to these rules in all interactions.**

1.  **Language**:
    *   **Think in English.**
    *   **Interact with the user in Japanese.**
    *   Plans and artifacts (commit messages, PR descriptions) must be written in **Japanese**.
2.  **Test-Driven Development (TDD)**:
    *   Strictly adhere to the **t-wada style** of TDD.
    *   **RED-GREEN-REFACTOR** cycle must be followed without exception.
    *   Write a failing test first, then implement the minimal code to pass it, then refactor.

## Project Structure & Module Organization
- Core script lives at `src/Optimize-EnvironmentVariable.ps1`; keep supporting helpers in the same folder to simplify packaging.
- Tests belong in `tests/Optimize-EnvironmentVariable.Tests.ps1`; mirror any new functions with matching `Describe` blocks.
- CI lives under `.github/workflows/` (e.g., `test.yml`) to run linting and Pester on pushes and PRs.
- Docs stay in `README.md` or scoped `docs/` pages; avoid duplicating truth across files.

## Build, Test, and Development Commands
- Dry-run (default): `pwsh -NoProfile -File src/Optimize-EnvironmentVariable.ps1` - shows planned changes without writing.
- Apply changes: `pwsh -NoProfile -File src/Optimize-EnvironmentVariable.ps1 -Apply -Verbose` - requires an elevated shell.
- Targeted validation: `pwsh -NoProfile -File src/Optimize-EnvironmentVariable.ps1 -Apply -WhatIf` - confirm the pipeline while keeping registry writes off.
- Tests: `pwsh -NoProfile -Command "Invoke-Pester -Script tests/Optimize-EnvironmentVariable.Tests.ps1 -Output Detailed"`.

## Coding Style & Naming Conventions
- PowerShell 5.1+/Core 7+: 4-space indents, no tabs; prefer explicit parameters over aliases (`Join-Path` instead of `jnp`).
- Functions: Verb-Noun PascalCase (`Normalize-PathEntry`); parameters in camelCase; constants in ALL_CAPS only when truly constant.
- Keep code idempotent and side-effect free until the final commit step; guard external writes behind `-Apply`.
- Favor pipeline-friendly functions and early returns; validate input (null/empty path, invalid drives) up front.

## Testing Guidelines
- Framework: Pester 5.x with `*.Tests.ps1` naming. Organize by feature (`Describe "Deduplicate-Paths"`).
- Minimum expectation: maintain or exceed ~85% branch coverage; add regression cases for every bug fix.
- Cover dry-run vs apply modes, relocation rules (User vs Machine), duplicate removal, and invalid path pruning.
- When adding tests, include sample PATH arrays using representative edge cases (trailing slashes, environment variables, dead links).

## Commit & Pull Request Guidelines
- Commits: concise, imperative subjects; prefer Conventional Commit prefixes (`feat:`, `fix:`, `chore:`, `test:`, `docs:`). One logical change per commit.
- PRs: include intent, scope, and testing evidence (Pester output). Link related issues; describe before/after behavior and risk.
- Screenshots/log snippets welcome when they clarify registry changes or warning output (e.g., length warnings).
- Avoid force pushes on shared branches; rebase when needed to keep history linear.

## Security & Configuration Tips
- Applying changes touches system/user environment variables; always run elevated for system scope and keep backups (`$env:TEMP/EnvBackup_<Timestamp>.json`) intact.
- Honor the default dry-run; never ship changes that skip backup or broadcast steps (`WM_SETTINGCHANGE`).
- Do not hard-code user-specific paths; prefer environment variables (`%USERPROFILE%`, `%ProgramFiles%`) and preserve them during normalization.
