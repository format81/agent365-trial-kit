# Contributing to agent365-trial-kit

Thanks for your interest! This is **unofficial, community content** (not a
Microsoft product). Contributions that make the trial easier to run, more robust,
or better documented are very welcome.

> Several capabilities here (Microsoft Agent 365 SDK/CLI, Entra Agent ID, the
> Graph `riskyAgents` API) are in **PREVIEW** and can change. Please note the
> CLI/SDK version you tested against in your PR.

## Ways to contribute

- 🐛 **Bug reports** — open an issue with steps to reproduce, the failing command,
  the full error output, your OS, and the `a365 --version`.
- 💡 **Feature requests** — describe the scenario and the outcome you want.
- 🔧 **Pull requests** — fixes, new scripts, docs, samples.

## Before you open a PR

1. **Never commit secrets.** Confirm nothing sensitive is staged:
   ```powershell
   git add -A
   git status --short   # .env, a365.config.json, a365.generated.config.json,
                        # and manifest/ must NOT appear
   ```
   These are covered by `.gitignore`. If one shows up, run
   `git rm --cached <file>` and fix the ignore rules.

2. **Keep it reproducible.** Do not hard-code tenant IDs, subscription IDs,
   resource names, endpoints, or secrets. Read them from parameters, prompts, or
   the config/`.env` templates.

3. **Test what you changed.**
   - PowerShell: run [PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview):
     ```powershell
     Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
     Invoke-ScriptAnalyzer -Path . -Recurse
     ```
   - Python: syntax-check the sources:
     ```powershell
     python -m compileall DEV/src
     ```
   - If you touched the DEV flow, run it end-to-end in a **non-production**
     tenant/subscription and confirm cleanup works:
     `DEV/scripts/04-Cleanup.ps1 -Scope all -DeleteAppService`.

## Style & conventions

- **PowerShell**: approved verbs (`Get-`, `New-`, `Set-`, `Grant-`, …), one
  responsibility per script, echo the real `az`/`a365`/Graph command being run,
  fail with actionable guidance (not raw exceptions). Keep the numbered-script
  ordering (`00`–`06`) meaningful.
- **Python**: standard library + the pinned deps in `requirements.txt`; keep the
  agent logic and hosting concerns separated (`agent.py` vs `app.py`).
- **Docs**: update the relevant `README.md` when behavior changes. English only.
- **Comments**: explain *why*, not just *what*. Mark anything preview-dependent.

## Commit messages

Short, imperative, scoped — e.g.:

```
deploy: enable Oryx build before zip deploy
docs: clarify manual governance upload step
ob4: add -CheckOnly summary line
```

## Pull request checklist

- [ ] No secrets or personal identifiers committed
- [ ] Scripts pass PSScriptAnalyzer / Python compiles
- [ ] Docs updated where needed
- [ ] Tested against a preview CLI version (note the version)
- [ ] Preview-dependent behavior is called out

## Security

Do **not** open a public issue for anything that looks like a secret leak or a
security problem. Instead, contact the maintainer privately (see the profile at
https://github.com/format81) and rotate any exposed credential immediately
(`a365 setup blueprint --show-secret` to view/regenerate the blueprint secret).

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
