import assert from 'node:assert/strict';
import test from 'node:test';
import { contractAmount, requireContractAmount } from '../src/lib/contractPricing.ts';

test('admin preserves the submitted price, including legacy contracts', () => {
  for (const amount of [299, 399, 424, 799, 361.5, 1199, 398]) {
    assert.equal(contractAmount({ status: 'awaitingPayment', totalFees: amount, totalPayable: 398 }), amount);
  }
});
test('draft uses its current quote and missing prices are not invented', () => {
  assert.equal(contractAmount({ status: 'draft', totalFees: 0, draftData: { financial: { totalPayable: 799 } } }), 799);
  assert.equal(contractAmount({ status: 'awaitingPayment' }), 0);
  assert.throws(() => requireContractAmount({ status: 'awaitingPayment' }));
});
