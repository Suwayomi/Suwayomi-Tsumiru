# Extension Store (#138) — progress ledger
Plan: ~/Documents/vault/sorayomi/plans/2026-07-23-extension-store-plan.md
Branch: extension-store (base f2a88264, worktree .claude/worktrees/extension-store)
Task 1: complete (commit 891d9ae1, review clean). Minor (defer to final): refresh-failure-after-successful-mutation toast edge case (screen add/delete flows); doc-shape-only test coverage ceiling.
Task 2: complete (commits 8f08a570 + e207dfe5, review approved). Schema = v2.3.2243, all 8 hard-gate items pass; forced fixes: AllCategories order args, bindTrackRecord nullability. Legacy-field sites carry intent-marker ignores (analyzer 12.1.0 doesn't flag same-package deprecation; markers are future-proofing). FYI for later tasks: fetchManga/fetchChapters + versionCode now deprecated; ExtensionFilterInput swapped isNsfw/repo→contentWarning.
Task 3: complete (commit 9fd6c6bb, 4 tests pass, analyze clean, full suite 1174/1174). ExtensionStoreRepository probe + classifyStoreProbe classifier + extensionStoreRepositoryProvider/extensionStoreSupportProvider; CRUD deferred to Task 4.
