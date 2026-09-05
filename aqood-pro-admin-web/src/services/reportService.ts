import { Contract, CONTRACT_STATUSES } from '@/types/contract';
import { AppUser } from '@/types/user';
import { formatShortDate, inRange, isToday } from '@/lib/dates';
import { contractAmount } from '@/lib/contractPricing';

export function summarizeContracts(contracts: Contract[]) {
  const byStatus = CONTRACT_STATUSES.map((status) => ({ status, count: contracts.filter((contract) => contract.status === status).length }));
  const completed = contracts.filter((contract) => contract.status === 'authenticated');
  const today = contracts.filter((contract) => isToday(contract.createdAt));
  const revenueBase = contracts.filter((contract) => ['processing', 'missingData', 'authenticated'].includes(contract.status));
  const totalFees = revenueBase.reduce((sum, contract) => sum + contractAmount(contract), 0);
  const commercialFees = revenueBase.filter((contract) => ['commercial', 'تجاري'].includes(String(contract.draftData?.type ?? contract.type ?? contract.contractType))).reduce((sum, contract) => sum + contractAmount(contract), 0);
  return {
    total: contracts.length,
    today: today.length,
    awaitingPayment: contracts.filter((contract) => contract.status === 'awaitingPayment').length,
    missingData: contracts.filter((contract) => contract.status === 'missingData').length,
    completed: completed.length,
    totalFees,
    commercialFees,
    residentialFees: totalFees - commercialFees,
    byStatus,
    byCity: Object.entries(contracts.reduce<Record<string, number>>((acc, contract) => {
      const city = contract.city || (contract.property as Record<string, unknown> | undefined)?.city || 'غير محدد';
      acc[String(city)] = (acc[String(city)] ?? 0) + 1;
      return acc;
    }, {})).map(([city, count]) => ({ city, count })),
  };
}

export function summarizeUsers(users: AppUser[]) {
  return {
    total: users.length,
    today: users.filter((user) => isToday(user.createdAt)).length,
    blocked: users.filter((user) => user.blocked || user.status === 'blocked').length,
  };
}

export function filterByDateRange<T extends { createdAt?: unknown }>(rows: T[], from?: string, to?: string) {
  if (!from && !to) return rows;
  return rows.filter((row) => inRange(row.createdAt, from, to));
}

export function newUsersByDay(users: AppUser[]) {
  const map = users.reduce<Record<string, number>>((acc, user) => {
    const day = formatShortDate(user.createdAt, 'غير محدد');
    acc[day] = (acc[day] ?? 0) + 1;
    return acc;
  }, {});
  return Object.entries(map).map(([day, count]) => ({ day, count }));
}
