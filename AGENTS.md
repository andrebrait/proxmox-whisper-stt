# proxmox-whisper-stt

This repository version-controls and backs up the deployment scripts, configuration and runbook of the whisper.cpp speech-to-text LXC on Proxmox VE, as used in Andre's setup. Its purpose is simply to keep these settings, configurations and scripts versioned and backed up; it is a record of a working setup, not a software project.

## Working rules

- Commit directly to `main` and push to `origin/main`. Pull requests and multiple branches are, in general, not necessary or desired.
- A temporary local worktree is fine for editing, but work from a detached `HEAD` (or delete any local branch afterwards), push the commits straight to `origin/main`, and remove the worktree when done. Do not push other branches.
- Changes need no pull-request review. A small adversarial review of each committed change is enough, and none is needed when the user has tested and attested the change.
