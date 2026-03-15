# AGENTS.md

## Skills

### Available skills


### How to use skills
- If the task matches a skill description or the user names the skill, open that `SKILL.md` first and follow it.
- Keep skill loading minimal: read only the skill file unless it explicitly points to extra local files.
- Prefer the project skill workflow over ad-hoc command sequences when they overlap.

## Workflow Requirements

- After implementing a feature or code change, wait for the user's review/approval before creating a git commit.
- Once the user confirms the change is approved, create the commit yourself instead of asking the user to commit manually.
- Perform future repository work on the `master` branch by default. If the branch does not exist yet, create and switch to it before continuing when feasible.
- Write commit messages that are concise but specific enough to describe the actual user-facing or code-level changes.
- Prefer Chinese commit messages unless the user explicitly asks for another language.

## File Standards

- Use `UTF-8` without BOM for text files.
- Use `LF` line endings for text files.
- Store project skills under `.codex/skills/`.
