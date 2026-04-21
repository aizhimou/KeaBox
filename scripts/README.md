# Scripts

## GitHub Packages Cleaner

Use [`cleanup-github-packages.sh`](./cleanup-github-packages.sh) to remove old GitHub Package versions.

It combines two common cleanup actions:

- delete untagged container versions
- keep only the newest N versions and delete older ones

Example:

```bash
./scripts/cleanup-github-packages.sh \
  --owner aizhimou \
  --package pigeon-pod-saas/api \
  --delete-untagged \
  --keep 5
```

Requirements:

- `gh` CLI installed
- `gh auth login` already completed
