# Account administration

More → Account → Manage users provides username search, pages of 25 users, account creation, role and permission editing, and registration/recovery codes. Search starts a new page sequence. The server has no user removal operation; the list explains that limitation. See [the screen](../../lib/src/features/account/presentation/manage_users_screen.dart) and [page providers](../../lib/src/features/account/data/account_administration.dart).

Administration requires supported accounts and current `MANAGE_USERS` access. The repository checks access before each administrative operation, including calls made through a retained repository. Unknown and unsupported capability states cannot admit these requests. Capability checks, current-account queries, personal settings, password changes, and unauthenticated code redemption retain their separate paths. See [AccountRepository](../../lib/src/features/account/data/account_repository.dart).

Permission updates replace the submitted permission list. The editor preserves grants it does not expose, including the unfinished NSFW grant. Only administrators see the USER/ADMIN selector; nonadministrators omit the role field. User 1 has no editable role, permission, or recovery control. Saving the current user's grants invalidates current-account access. See [the editors](../../lib/src/features/account/presentation/account_admin_dialogs.dart).

Issued codes live only in their result dialog and can be copied before dismissal. Account creation and code issuance bypass the GraphQL cache. Expiry uses server epoch seconds and the local date/time format. Outstanding codes show their purpose, recovery target, and expiry; revocation requires confirmation. See [code screens](../../lib/src/features/account/presentation/account_codes_screen.dart).

The focused tests cover transport admission, search and paging, omitted role fields, immutable built-in accounts, creation errors, code caching, copy, and cancellation of revocation:

- `test/src/features/account/account_administration_test.dart`
- `test/src/features/account/account_administration_ui_test.dart`
