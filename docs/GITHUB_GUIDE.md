# GitHub Guide

## Review before publishing

1. Confirm `.env` is ignored and contains no real credential in any staged file.
2. Use only fictional demonstration data.
3. Run the Oracle scripts/tests on a disposable schema and update the test record only with observed results.
4. Replace title-page placeholders only if you want personal details in the repository; otherwise leave them generic.

## Create and push the repository from PowerShell

Create an empty GitHub repository named `LedgerLens` in the GitHub web interface, then run these commands from the project folder:

```powershell
git init
git add .
git status
git commit -m "Build LedgerLens Oracle transaction monitoring project"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/LedgerLens.git
git push -u origin main
```

Replace `YOUR-USERNAME`. Review the `git status` output before committing. To check whether a local environment file is ignored:

```powershell
git check-ignore .env
```

## Future changes

Use descriptive commits and keep Oracle changes with corresponding documentation/test updates. Do not commit database exports containing non-synthetic data, passwords, private keys, or session files. GitHub Pages is not configured because this repository contains SQL and a local Flask app rather than a static website.
