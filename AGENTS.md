# AGENTS.md

## File Standards

- Use `UTF-8` without BOM for text files.
- Use `LF` line endings for text files.
- Store project skills under `skills/`.

## Skills

### Available skills


### How to use skills
- If the task matches a skill description or the user names the skill, open that `SKILL.md` first and follow it.
- Keep skill loading minimal: read only the skill file unless it explicitly points to extra local files.
- Prefer the project skill workflow over ad-hoc command sequences when they overlap.

## Workflow Requirements

- After implementing a feature or code change, wait for the user's review/approval before creating a git commit.
<!-- - Once the user confirms the change is approved, create the commit yourself instead of asking the user to commit manually. -->
- Perform future repository work on the `master` branch by default. If the branch does not exist yet, create and switch to it before continuing when feasible.
- Write commit messages that are concise but specific enough to describe the actual user-facing or code-level changes.
- Prefer Chinese commit messages unless the user explicitly asks for another language.

## Planning Records

- Use `PLAN.md` as the project-level planning index and operation record entry point.
- Put concrete planning details under `plan/`, one Markdown file per topic.
- Keep implementation steps, validation criteria, risks, and operation traces in the topic file under `plan/`.
- Do not turn `PLAN.md` into a detailed design document for a single topic.
- Do not require dates in planning files unless the user explicitly asks for them.
- After completing key implementation or verification steps, update the corresponding topic file under `plan/` so the work remains traceable.

