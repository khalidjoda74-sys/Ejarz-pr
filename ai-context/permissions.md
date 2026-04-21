# Permissions

## Existing role sources

- `lib/ui/ai_chat/ai_chat_permissions.dart`
- `lib/ui/ai_chat/core/ai_permission_guard.dart`

## Effective AI permission groups

- `owner`, `officeOwner`
  full read/write/report/navigation access
- `officeStaff`
  read + report + help
- `officeClient`, `viewOnly`
  restricted read + help

## Registry permission keys

- `properties.view/create/update`
- `units.view/create/update`
- `owners.view/create/update`
- `tenants.view/create/update`
- `contracts.view/create/update/terminate`
- `invoices.view/create`
- `payments.view/create/reverse`
- `maintenance.view/create/update`
- `expenses.view/create`
- `reports.view`
- `reports.financial`
- `exports.create`
- `app.help`
- `app.navigate`
