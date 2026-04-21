const DEMO_PACKAGE_SNAPSHOT = Object.freeze({
  packageId: 'demo_unlimited',
  name: 'تجريبي',
  packageName: 'تجريبي',
  isActive: true,
  limits: {
    officeUsersUnlimited: true,
    clientsUnlimited: true,
    propertiesUnlimited: true,
    officeUsers: null,
    clients: null,
    properties: null,
  },
  pricing: {
    monthly: null,
    yearly: null,
  },
});

function buildDemoUnlimitedPackageSnapshot() {
  return {
    packageId: DEMO_PACKAGE_SNAPSHOT.packageId,
    name: DEMO_PACKAGE_SNAPSHOT.name,
    packageName: DEMO_PACKAGE_SNAPSHOT.packageName,
    isActive: DEMO_PACKAGE_SNAPSHOT.isActive,
    limits: {
      ...DEMO_PACKAGE_SNAPSHOT.limits,
    },
    pricing: {
      ...DEMO_PACKAGE_SNAPSHOT.pricing,
    },
  };
}

module.exports = {
  buildDemoUnlimitedPackageSnapshot,
};
