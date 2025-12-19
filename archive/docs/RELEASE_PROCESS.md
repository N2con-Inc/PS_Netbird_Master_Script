# Release Process

This project follows semantic versioning:
- Bug fix or tweak: +0.0.1
- New feature or function: +0.1.0
- Major version: +1.0.0 (manual only)

Every version change MUST trigger a new GitHub Release.

## Pre-release checklist
1) Ensure netbird.extended.ps1 header Version reflects the new version.
2) Update README.md Version History summary.
3) If needed, update docs/releases/VERSION.md with release notes.

## Tagging and releasing
1) Commit and push all changes on main.
2) Tag the release:
   - `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
   - `git push origin vX.Y.Z`
3) Create the GitHub release (choose one):
   - Using GitHub CLI:
     - `gh release create vX.Y.Z netbird.extended.ps1 --title "PS NetBird Master Script vX.Y.Z" --notes-file docs/releases/vX.Y.Z.md`
   - Or via GitHub UI on the Releases page.

## Expectations
- The script version, Git tag, and GitHub Release tag MUST match exactly.
- Use SSH for the repository remote.
- Keep releases focused and small; prefer simplicity.