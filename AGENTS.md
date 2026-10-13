# AGENTS.md

## Project
- zsh CLI that plans AWS compute architecture from an interactive interview and writes Mermaid diagram, graph audit, and a versioned JSON plan.
- No package manifest or lockfile: plain zsh plus system/global tools.

## Commands
Run the planner:

```sh
AWS_SETUP_REGION=us-east-1 ./bin/aws-plan/aws-plan
```

Or create a local config first:

```sh
cp config/local.env.example config/local.env
# set AWS_SETUP_REGION in config/local.env
```

Run the full test suite (from repo root):

```sh
zsh tests/check.zsh
```

Requirements: zsh, jq, uuidgen (`uuid-runtime` on Debian), and mmdc. `chafa` is only for the optional terminal image preview. Tests fail without mmdc even though the planner itself skips rendering without it.

Validate a generated plan:

```sh
zsh bin/aws-plan/aws-plan-plan-validate.zsh validate --plan out/plan.json
```

## Config And Environment
- Config load order: `AWS_SETUP_CONFIG` if it points at an existing file; else repo `config/local.env`; else `~/.config/pc-aws/local.env`.
- `AWS_SETUP_OUT` overrides the default output directory (repo `out/`); the script resolves repo root from its own path, so the default output is not cwd-dependent.
- Region selection: `AWS_REGION`, then `AWS_DEFAULT_REGION`, then `aws configure get region`. `AWS_SETUP_REGION` becomes `AWS_DEFAULT_REGION`, so an explicit `AWS_REGION` still wins.
- AWS credentials are not required for planning. `out/` and local env files are ignored.

## Architecture
- Entry point is `bin/aws-plan/aws-plan`; it dot-sources the modules in `bin/aws-plan/` in a fixed order. Add a new module to that list and keep names/functions aligned with call sites.
- State is mutable global zsh vars/arrays (`aws-plan-state.zsh`, `aws-plan-services.zsh`, etc.); `SERVICES`, `RESOURCE_*`, and `RESOURCE_EDGES` are consumed by graph generation and plan writing.
- Main flow: questions -> derive -> region -> report -> graph registry/resources/relationships/active/layout/edges/audit -> plan write -> Mermaid render.
- `aws-plan-write-plan` calls `aws-plan-plan.zsh build ...`; plan IDs come from `uuidgen`.
- Generated outputs: `architecture.mmd`, `architecture.svg`, `architecture.png`, `graph-audit.md`, `plan.json`, and `plans/<plan-id>.json`.

## Important Quirks
- Tests exercise the whole CLI through scripted stdin; there are no isolated unit tests. When editing, rely on targeted manual runs and the full suite.
- `ask_choice` accepts blank input as the default. `ask_yes_no` does not; scripted answers must be `y`, `n`, or `e`.
- yes/no prompts are handled a line at a time when stdin is not a TTY and only the first character is used.
- The planner calls `clear` on startup and disables colors when stdout is not a TTY, `NO_COLOR` is set, or `TERM=dumb`.
- mmdc absence is non-fatal in the planner but makes tests fail (`rendering skipped`).
- Prompt `e` prints yes/no use-case examples.
- Render errors append to `out/mermaid.log`; inspect it for Mermaid parse errors.
- Interview prompt changes alter the hardcoded scripted answer counts in `tests/check.zsh`.
- The entrypoint resolves the repo root from its own path, so modules and the default `out/` work from any current directory.
- Do not commit generated files under `out/` or `config/local.env`.

## Development Guardrails
- Read the affected module and all files it touches before editing. Do not edit an output artifact instead of its source.
- There are no single-test commands: reproduce a scenario with the answer sequences in `tests/check.zsh` when manual verification is enough.
- A question-count change is a contract change: update the scripted answer sequences in the same patch.
- Before claiming done, run `zsh tests/check.zsh` and report compilation-free Markdown output checks from the test log.
