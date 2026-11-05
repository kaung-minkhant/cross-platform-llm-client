# Fork workflow (kaung-minkhant/cross-platform-llm-client)

This file is **fork-only**. It lives on the fork's `main` and must never appear
in a branch that is sent to upstream. If you are on a branch that doesn't have
it, read it with `git show main:AGENTS.md`.

## Remotes

| Remote     | URL                                                        | Use                         |
|------------|------------------------------------------------------------|-----------------------------|
| `origin`   | https://github.com/kaung-minkhant/cross-platform-llm-client | the fork; push branches here |
| `upstream` | https://github.com/orailnoor/cross-platform-llm-client      | original project; PR target |

## Branch roles

| Branch                | Based on        | Contains                          | Goes upstream? |
|-----------------------|-----------------|-----------------------------------|----------------|
| `main`                | `upstream/main` | upstream + fork-only commits      | **never**      |
| `chore/nix-devshell`  | `main`          | `flake.nix`, `flake.lock`, `.envrc`, `.gitignore` entry | no |
| `fix/*`, `feat/*`     | `upstream/main` | one upstream-friendly change only | yes, via PR    |

Fork-only commits on `main`: the Nix dev shell and this file. Anything else
that is personal (local config, notes, experiments) also goes there, never in a
`fix/*` or `feat/*` branch.

## Dev environment

The flake pins Flutter **3.38.4** (Dart 3.10.3), the version in `.metadata`,
from a separate nixpkgs input. The main input is `nixos-26.05`. JDK 17 is
included. There is no Android SDK/NDK, so APK builds don't work from it.

- **On `main` (or a branch from it):** direnv loads the shell automatically.
  Run `direnv allow` once. Run commands as `direnv exec . flutter test`.
- **On any branch without `flake.nix`** (all `fix/*`/`feat/*` branches):
  use the flake from `main` by reference. Run it from the repo root:

  ```bash
  nix develop "git+file://$PWD?ref=main" --command flutter test
  ```

  This reads the *committed* flake on `main`, so it doesn't touch your branch.
  The `--command` form is also what an agent should use (no interactive shell).

If `flutter` is "command not found", you are on a branch without the flake and
used the plain command. Use the `nix develop` form above.

## Making a change for upstream

1. Sync and branch from **upstream**, not from `main`:
   ```bash
   git fetch upstream
   git switch -c fix/<short-name> upstream/main
   ```
2. Make one small, focused change, with tests. Follow the surrounding style.
3. Test with the `nix develop` command above. Run only relevant tests first,
   then the full `flutter test` if the change is broad.
4. Check `git status` before committing. Only the intended files should show.
   (On Flutter 3.38.4 `pub get` and `test` leave tracked files alone. If
   `pubspec.lock` or `analysis_options.yaml` change, the wrong Flutter version
   is in use. Do not commit that. Revert with `git checkout -- <file>`.)
5. Commit with a conventional message (`fix(scope): ...`, `feat(scope): ...`,
   `chore: ...`), matching the repo history.
6. Push to the fork: `git push -u origin fix/<short-name>`.
7. Open the PR from that branch to `upstream`. Never from `main`.

## Getting the change into the fork's `main`

So your own builds include it, merge the branch into `main` after pushing it:

```bash
git switch main
git merge fix/<short-name>
```

When the PR is later merged upstream, the same change appears twice in history.
That merges cleanly because the contents are identical.

## Staying in sync with upstream

```bash
git fetch upstream
git switch main
git merge upstream/main    # a merge commit each time; the fork-only files never conflict
git push origin main
```

Do not rebase `main` onto upstream. It is published on the fork.

## Fork-only changes

Branch from `main` (not `upstream/main`), merge back into `main`. direnv works
normally there.

## Rules for the agent

- Don't push, force-push, open PRs, or change remotes unless asked. Prepare the
  commits and give the user the exact push command.
- Never set `git config --global`. The repo-local identity is already set.
- Never commit to `main` for upstream work. Never put fork-only files
  (`flake.*`, `.envrc`, `AGENTS.md`) in a `fix/*` or `feat/*` branch.
- Before branching for an upstream change, confirm `git status` is clean and
  say which base you are using.
- Don't make network/API calls (e.g. the GitHub API with curl) without asking.
- Keep changes small. Put unrelated improvements in a separate branch.
- State plainly what was and wasn't tested. If tests were not run on the final
  branch contents, say so.
