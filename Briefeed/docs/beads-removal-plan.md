# Beads Removal Plan

Run these in order.

## Phase 1: Clean Claude integration (while `bd` still works)

```bash
bd setup claude --remove
```

## Phase 2: Kill all daemons

```bash
pkill -f "bd daemon"
```

## Phase 3: Remove per-repo data (all 23 repos)

### 3a. Remove .beads dirs, git config, and beads-worktrees

```bash
for repo in \
  ~/ericode/thresholdnye \
  ~/ericode/Protact2 \
  ~/ericode/podrip \
  ~/ericode/detoxbio \
  ~/ericode/wpp \
  ~/ericode/domain-hunter \
  ~/ericode/elsa-monorepo \
  ~/ericode/destructive-guard/destructive_command_guard \
  ~/ericode/mens-health-brand \
  ~/ericode/elsa-rekall \
  ~/ericode/else-wise-path/elsa-wise-path \
  ~/ericode/briefeed-app/briefeed-ios/Briefeed \
  ~/ericode/ocr-dojo \
  ~/ericode/clawcierge \
  ~/ericode/colin-drone \
  ~/ericode/therry-design-demos/TherryDesignDemo \
  ~/ericode/therry-main/therry-prompt-generator \
  ~/ericode/therry-main \
  ~/ericode/therry-main/therry-swift \
  ~/ericode/therry-main/therry-website
do
  echo "--- Cleaning $repo ---"
  rm -rf "$repo/.beads"
  rm -rf "$repo/.git/beads-worktrees" 2>/dev/null
  (cd "$repo" && git config --unset beads.role 2>/dev/null)
  (cd "$repo" && git config --unset merge.beads.driver 2>/dev/null)
  (cd "$repo" && git config --unset merge.beads.name 2>/dev/null)
done
```

### 3b. Delete beads-only .gitattributes files

```bash
for repo in \
  ~/ericode/thresholdnye \
  ~/ericode/Protact2 \
  ~/ericode/elsa-monorepo \
  ~/ericode/destructive-guard/destructive_command_guard \
  ~/ericode/mens-health-brand \
  ~/ericode/else-wise-path/elsa-wise-path \
  ~/ericode/briefeed-app/briefeed-ios/Briefeed \
  ~/ericode/clawcierge \
  ~/ericode/colin-drone \
  ~/ericode/therry-design-demos/TherryDesignDemo \
  ~/ericode/therry-main/therry-prompt-generator \
  ~/ericode/therry-main/therry-swift
do
  rm -f "$repo/.gitattributes"
done
```

### 3c. detoxbio: remove only beads lines (keep git-crypt lines)

```bash
sed -i '' '/beads/d' ~/ericode/detoxbio/.gitattributes
```

### 3d. Remove beads git hooks (this is what causes the "bd command not found" warnings)

All of these are pure beads shims — safe to delete. Briefeed's pre-commit is SwiftLint, NOT beads, so it is excluded.

```bash
rm -f ~/ericode/thresholdnye/.git/hooks/pre-commit
rm -f ~/ericode/thresholdnye/.git/hooks/post-merge
rm -f ~/ericode/Protact2/.git/hooks/pre-commit
rm -f ~/ericode/Protact2/.git/hooks/pre-push
rm -f ~/ericode/Protact2/.git/hooks/prepare-commit-msg
rm -f ~/ericode/Protact2/.git/hooks/post-merge
rm -f ~/ericode/Protact2/.git/hooks/post-checkout
rm -f ~/ericode/detoxbio/.git/hooks/pre-commit
rm -f ~/ericode/detoxbio/.git/hooks/post-merge
rm -f ~/ericode/elsa-monorepo/.git/hooks/pre-commit
rm -f ~/ericode/elsa-monorepo/.git/hooks/pre-push
rm -f ~/ericode/elsa-monorepo/.git/hooks/post-merge
rm -f ~/ericode/elsa-monorepo/.git/hooks/post-checkout
rm -f ~/ericode/mens-health-brand/.git/hooks/pre-commit
rm -f ~/ericode/mens-health-brand/.git/hooks/post-merge
rm -f ~/ericode/clawcierge/.git/hooks/pre-commit
rm -f ~/ericode/clawcierge/.git/hooks/post-merge
rm -f ~/ericode/colin-drone/.git/hooks/pre-commit
rm -f ~/ericode/colin-drone/.git/hooks/post-merge
rm -f ~/ericode/therry-design-demos/TherryDesignDemo/.git/hooks/pre-commit
rm -f ~/ericode/therry-design-demos/TherryDesignDemo/.git/hooks/post-merge
rm -f ~/ericode/therry-main/therry-prompt-generator/.git/hooks/pre-commit
rm -f ~/ericode/therry-main/therry-prompt-generator/.git/hooks/pre-push
rm -f ~/ericode/therry-main/therry-prompt-generator/.git/hooks/post-merge
rm -f ~/ericode/therry-main/therry-prompt-generator/.git/hooks/post-checkout
rm -f ~/ericode/therry-main/therry-swift/.git/hooks/pre-commit
rm -f ~/ericode/therry-main/therry-swift/.git/hooks/pre-push
rm -f ~/ericode/therry-main/therry-swift/.git/hooks/prepare-commit-msg
rm -f ~/ericode/therry-main/therry-swift/.git/hooks/post-merge
rm -f ~/ericode/therry-main/therry-swift/.git/hooks/post-checkout
```

### 3e. Clean worktree copies

```bash
rm -rf ~/ericode/detoxbio/.worktrees/halfmoon-demo/.beads
rm -rf ~/ericode/elsa-monorepo/.worktrees/mvp-implementation/.beads
rm -f ~/ericode/detoxbio/.worktrees/halfmoon-demo/.gitattributes
rm -f ~/ericode/elsa-monorepo/.worktrees/mvp-implementation/.gitattributes
rm -rf ~/ericode/Protact2/.beads/.beads
```

## Phase 4: Remove global components

```bash
rm ~/go/bin/bd
rm -rf ~/.beads
rm -rf ~/.vscode/extensions/devtheops.beads-ui-0.0.4
rm -rf ~/.claude/plugins/marketplaces/beads-marketplace
rm -rf ~/.claude/plugins/cache/beads-marketplace
rm -rf ~/.claude/plugins/data/beads-beads-marketplace
```

## Phase 5: Edit Claude settings — ALREADY DONE

The `"beads@beads-marketplace": true` line was already removed from `~/.claude/settings.json`.

## Phase 6: Optional cleanup

```bash
rm -rf ~/.claude/projects/-Users-me-ericode-colin-drone--git-beads-worktrees-improve-shot-individual-setup
rm -rf ~/.claude/projects/-Users-me-ericode-elsa-monorepo--git-beads-worktrees-feat-tdd-implementation
```
