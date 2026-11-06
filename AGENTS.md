# proxmox-whisper-stt

This repository version-controls and backs up the deployment scripts, configuration and runbook of the whisper.cpp speech-to-text LXC on Proxmox VE, as used in Andre's setup. Its purpose is simply to keep these settings, configurations and scripts versioned and backed up; it is a record of a working setup, not a software project.

## Working rules

- Commit directly to `main` and push to `origin/main`. Pull requests and multiple branches are, in general, not necessary or desired.
- Work in the primary checkout; worktrees are generally neither necessary nor desirable in this repository. Use one only when editing in place risks breaking a live setup, for example when the file being changed is the same one that running software auto-reloads its settings from: make the change in a different location and copy only the final result to its destination, preserving the original file's inode when that works better for the software involved. Work from a detached `HEAD`, push the commits straight to `origin/main`, and remove the worktree when done. Do not push other branches.
- Changes need no pull-request review. A small adversarial review of each committed change is enough, and none is needed when the user has tested and attested the change.
