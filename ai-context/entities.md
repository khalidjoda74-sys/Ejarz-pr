# Entities

- `Property` from `lib/models/property.dart`
  fields: `id`, `name`, `type`, `address`, `price`, `currency`, `rooms`, `area`, `floors`, `totalUnits`, `occupiedUnits`, `rentalMode`, `parentBuildingId`, `description`, `isArchived`, `documentType`, `documentNumber`, `documentDate`, `documentAttachmentPaths`, `electricityMode`, `waterMode`, `waterAmount`

- `Tenant` from `lib/models/tenant.dart`
  fields: `id`, `fullName`, `nationalId`, `phone`, `email`, `nationality`, `idExpiry`, `notes`, `tags`, `clientType`, `companyName`, `serviceSpecialization`, `attachmentPaths`, `isArchived`, `isBlacklisted`, `activeContractsCount`

- `Contract` from `lib/ui/contracts_screen.dart`
  fields: `id`, `serialNo`, `tenantId`, `propertyId`, `startDate`, `endDate`, `rentAmount`, `totalAmount`, `currency`, `term`, `paymentCycle`, `advancePaid`, `dailyCheckoutHour`, `notes`, `attachmentPaths`, `isTerminated`, `terminatedAt`, `isArchived`

- `Invoice` from `lib/ui/invoices_screen.dart`
  fields: `id`, `serialNo`, `tenantId`, `contractId`, `propertyId`, `issueDate`, `dueDate`, `amount`, `paidAmount`, `currency`, `note`, `paymentMethod`, `attachmentPaths`, `maintenanceRequestId`, `isArchived`, `isCanceled`

- `MaintenanceRequest` from `lib/ui/maintenance_screen.dart`
  fields: `id`, `serialNo`, `propertyId`, `tenantId`, `title`, `description`, `requestType`, `priority`, `status`, `scheduledDate`, `executionDeadline`, `completedDate`, `cost`, `assignedTo`, `providerSnapshot`, `attachmentPaths`, `invoiceId`, `periodicServiceType`, `periodicCycleDate`
