import type { Contract } from '../types/contract';

// Use the quote recorded with the contract; never reprice historical contracts.
export function contractAmount(contract: Contract): number {
  const candidates = contract.status === 'draft'
    ? [contract.draftData?.financial?.totalPayable, contract.totalFees, contract.totalPayable]
    : [contract.totalFees, contract.totalPayable, contract.draftData?.financial?.totalPayable];
  for (const value of candidates) {
    if (value == null || value === '') continue;
    const amount = Number(value);
    if (Number.isFinite(amount) && amount > 0) return amount;
  }
  return 0;
}

export function requireContractAmount(contract: Contract): number {
  const amount = contractAmount(contract);
  if (amount <= 0) throw new Error('لا توجد رسوم صالحة محفوظة لهذا العقد. راجع بيانات التسعير قبل طلب الدفع.');
  return amount;
}
