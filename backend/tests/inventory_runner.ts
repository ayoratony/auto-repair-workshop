import { PrismaClient } from '@prisma/client';
import express from 'express';
import http from 'http';
import { createInventoryRouter } from '../src/inventory';

// Test runner for Workshop Inventory module
async function runTests() {
  console.log('🚀 Starting Workshop Inventory Test Suite...');
  
  // Use connection from environment (configured for test branch)
  const prisma = new PrismaClient();
  await prisma.$connect();
  console.log('✅ Connected to Neon database branch.');

  // Create or get active test tenant
  const tenant = await prisma.tenant.upsert({
    where: { id: 'test-inventory-tenant' },
    update: {},
    create: {
      id: 'test-inventory-tenant',
      name: 'AutoKe Inventory Test Workshop',
      address: 'Test Workshop Ave, Nairobi',
      taxPin: 'P051239999Z',
    },
  });
  const tenantId = tenant.id;

  // Set up Express test app
  const app = express();
  app.use(express.json());
  app.use('/api/inventory', createInventoryRouter(prisma, async () => tenantId));

  const server = http.createServer(app);
  await new Promise<void>((resolve) => server.listen(0, resolve));
  const port = (server.address() as any).port;
  const baseUrl = `http://localhost:${port}/api/inventory`;

  async function api(path: string, options: { method?: string; role?: string; name?: string; body?: any } = {}) {
    const res = await fetch(`${baseUrl}${path}`, {
      method: options.method || 'GET',
      headers: {
        'Content-Type': 'application/json',
        'x-user-role': options.role || 'ADMIN',
        'x-user-name': options.name || 'Test User',
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });
    const status = res.status;
    let data: any = null;
    try {
      data = await res.json();
    } catch {
      data = null;
    }
    return { status, data };
  }

  function assert(cond: boolean, msg: string) {
    if (!cond) {
      console.error(`❌ ASSERTION FAILED: ${msg}`);
      throw new Error(`Assertion failed: ${msg}`);
    }
    console.log(`  ✓ ${msg}`);
  }

  try {
    // -------------------------------------------------------------
    // Test 1: Category Setup (Spare Part, Consumable, Tool Asset)
    // -------------------------------------------------------------
    console.log('\n--- Test 1: Distinct Inventory Categories Setup ---');
    
    // A. Spare Part (resale / customer repair)
    const sparePart = await prisma.partCatalog.create({
      data: {
        partNumber: `BP-${Date.now()}`,
        description: 'Toyota Brake Pads (Front)',
        brand: 'Bosch',
        costPrice: 2500,
        unitPrice: 4500,
        stockQuantity: 10,
        reorderLevel: 3,
        location: 'Bay 1 Rack A',
        tenantId,
      },
    });
    assert(sparePart.stockQuantity === 10, 'Spare part created with initial stock 10');

    // B. Internal Consumable (workshop supplies, internal use)
    const { status: itemStatus, data: consumable } = await api('/items', {
      method: 'POST',
      role: 'STOREKEEPER',
      body: {
        sku: `GLOVE-${Date.now()}`,
        name: 'Heavy Duty Nitrile Gloves (Box of 100)',
        unit: 'box',
        quantity: 20,
        unitCost: 1200,
        location: 'Supply Locker 2',
      },
    });
    assert(itemStatus === 200 && consumable.quantityOnHand === 20, 'Consumable registered with 20 boxes');

    // C. Reusable Company Tool / Equipment
    const { status: assetStatus, data: toolAsset } = await api('/assets', {
      method: 'POST',
      role: 'STOREKEEPER',
      body: {
        assetNumber: `SCAN-${Date.now()}`,
        name: 'Autel MaxiSys Pro OBD-II Scanner',
        cost: 150000,
        serialNumber: 'AUTEL-9921-X',
        condition: 'GOOD',
        isFixed: false,
        location: 'Electronics Bay',
      },
    });
    assert(assetStatus === 200 && toolAsset.status === 'AVAILABLE', 'Diagnostic scanner asset registered as AVAILABLE');

    // D. Fixed Equipment
    const { status: liftStatus, data: liftAsset } = await api('/assets', {
      method: 'POST',
      role: 'STOREKEEPER',
      body: {
        assetNumber: `LIFT-${Date.now()}`,
        name: 'Rotary 4-Post Hydraulic Workshop Lift',
        cost: 650000,
        isFixed: true,
        location: 'Bay 3',
        department: 'Heavy Mechanical',
      },
    });
    assert(liftStatus === 200 && liftAsset.status === 'FIXED', 'Hydraulic Lift registered as permanent FIXED asset');

    // -------------------------------------------------------------
    // Test 2: Role Permissions Enforcement
    // -------------------------------------------------------------
    console.log('\n--- Test 2: Role Permissions Guard ---');
    
    // Technician attempting to approve requests or adjust stock -> FORBIDDEN (403)
    const techAdjust = await api('/adjustments', {
      method: 'POST',
      role: 'MECHANIC',
      body: { category: 'SPARE_PART', itemId: sparePart.id, delta: 5, reason: 'Unauthorized boost' },
    });
    assert(techAdjust.status === 403, 'Technician blocked from stock adjustments (403)');

    // Storekeeper attempting to write-off asset without Manager role -> FORBIDDEN (403)
    const storekeeperWriteoff = await api(`/assets/${toolAsset.id}/report`, {
      method: 'POST',
      role: 'STOREKEEPER',
      body: { kind: 'WRITE_OFF', reason: 'Attempt writeoff without manager' },
    });
    assert(storekeeperWriteoff.status === 403, 'Storekeeper blocked from writing off assets (403)');

    // -------------------------------------------------------------
    // Test 3: Technician Item Request Linking to Job Card & Vehicle
    // -------------------------------------------------------------
    console.log('\n--- Test 3: Technician Item Request Creation ---');
    
    // Create test customer, vehicle and job card
    const customer = await prisma.customer.create({
      data: { name: 'James Kariuki', phone: '0712345678', tenantId },
    });
    const vehicle = await prisma.vehicle.create({
      data: { registrationNo: 'KDE 456X', make: 'Toyota', model: 'Prado', customerId: customer.id },
    });
    const jobCard = await prisma.jobCard.create({
      data: {
        jobNumber: `JC-${Date.now().toString().slice(-5)}`,
        customerId: customer.id,
        vehicleId: vehicle.id,
        tenantId,
        technician: 'Kamau Tech',
        workRequested: 'Full Brake System Overhaul & Diagnostics',
      },
    });

    const { status: reqStatus, data: reqData } = await api('/requests', {
      method: 'POST',
      role: 'MECHANIC',
      name: 'Kamau Tech',
      body: {
        jobCardId: jobCard.id,
        department: 'Mechanical Bay 1',
        reason: 'Required for scheduled brake service and scanner diagnosis',
        lines: [
          { category: 'SPARE_PART', itemId: sparePart.id, quantity: 2 },
          { category: 'CONSUMABLE', itemId: consumable.id, quantity: 2 },
          { category: 'TOOL_EQUIPMENT', itemId: toolAsset.id, quantity: 1, expectedReturnAt: new Date(Date.now() + 86400000).toISOString() },
        ],
      },
    });
    assert(reqStatus === 200 && reqData.status === 'PENDING', 'Request created in PENDING status');
    assert(reqData.lines.length === 3, 'Request contains all 3 distinct category lines');
    const requestId = reqData.id;

    // Check storekeeper notification generated
    const notifications = await api('/notifications?unread=1', { role: 'STOREKEEPER' });
    assert(notifications.data.some((n: any) => n.requestId === requestId), 'Storekeeper received notification for new request');

    // -------------------------------------------------------------
    // Test 4: Approval Separation from Issuance (Stock Must NOT Deduct on Approval)
    // -------------------------------------------------------------
    console.log('\n--- Test 4: Approval Does NOT Deduct Stock ---');
    
    // First attempt: Storekeeper approves high-value equipment -> 403 (needs Manager)
    const storekeeperApprove = await api(`/requests/${requestId}/decision`, {
      method: 'POST',
      role: 'STOREKEEPER',
      name: 'Storekeeper John',
      body: { action: 'APPROVE', notes: 'Storekeeper review' },
    });
    assert(storekeeperApprove.status === 403, 'Storekeeper blocked from approving high-value request (> 20k KES) without Manager (403)');

    // Workshop Manager approves exceptional request -> 200
    const { status: approveStatus, data: approveData } = await api(`/requests/${requestId}/decision`, {
      method: 'POST',
      role: 'MANAGER',
      name: 'Workshop Manager Alex',
      body: { action: 'APPROVE', notes: 'Approved for Bay 1 repair by Manager' },
    });
    assert(approveStatus === 200 && approveData.status === 'APPROVED', 'Request marked as APPROVED by Workshop Manager');

    // Verify stock levels are completely untouched!
    const partAfterApprove = await prisma.partCatalog.findUnique({ where: { id: sparePart.id } });
    const consAfterApprove = await prisma.inventoryItem.findUnique({ where: { id: consumable.id } });
    const toolAfterApprove = await prisma.toolAsset.findUnique({ where: { id: toolAsset.id } });
    assert(partAfterApprove!.stockQuantity === 10, 'Spare part stock remains 10 after approval (no premature deduction)');
    assert(consAfterApprove!.quantityOnHand === 20, 'Consumable stock remains 20 after approval');
    assert(toolAfterApprove!.status === 'AVAILABLE', 'Tool asset remains AVAILABLE after approval');

    // -------------------------------------------------------------
    // Test 5: Insufficient Stock Guard on Issuance
    // -------------------------------------------------------------
    console.log('\n--- Test 5: Insufficient Stock Protection ---');
    
    // Request more than available
    const excessiveReq = await api('/requests', {
      method: 'POST',
      role: 'MECHANIC',
      name: 'Kamau Tech',
      body: {
        jobCardId: jobCard.id,
        reason: 'Testing excessive quantity',
        lines: [{ category: 'SPARE_PART', itemId: sparePart.id, quantity: 50 }], // only 10 in stock
      },
    });
    await api(`/requests/${excessiveReq.data.id}/decision`, {
      method: 'POST',
      role: 'STOREKEEPER',
      body: { action: 'APPROVE', notes: 'Approved' },
    });
    const excessiveIssue = await api(`/requests/${excessiveReq.data.id}/issue`, {
      method: 'POST',
      role: 'STOREKEEPER',
      body: {
        lines: [{ lineId: excessiveReq.data.lines[0].id, quantity: 50 }],
      },
    });
    assert(excessiveIssue.status === 409, 'Excessive stock issuance rejected with 409 Conflict');

    // -------------------------------------------------------------
    // Test 6: Partial Issuance and Multi-Stage Issuance
    // -------------------------------------------------------------
    console.log('\n--- Test 6: Partial Issuance Workflow ---');
    
    const partLine = approveData.lines.find((l: any) => l.category === 'SPARE_PART');
    const consLine = approveData.lines.find((l: any) => l.category === 'CONSUMABLE');
    const toolLine = approveData.lines.find((l: any) => l.category === 'TOOL_EQUIPMENT');

    // Issue only 1 of the 2 spare parts first (Partial Issuance)
    const partialIssue = await api(`/requests/${requestId}/issue`, {
      method: 'POST',
      role: 'STOREKEEPER',
      name: 'Storekeeper John',
      body: {
        receivedBy: 'Kamau Tech',
        lines: [{ lineId: partLine.id, quantity: 1 }],
      },
    });
    assert(partialIssue.status === 200 && partialIssue.data.status === 'PARTIALLY_ISSUED', 'Request status transitioned to PARTIALLY_ISSUED');

    const partAfterPartial = await prisma.partCatalog.findUnique({ where: { id: sparePart.id } });
    assert(partAfterPartial!.stockQuantity === 9, 'Spare part stock decremented from 10 to 9 after partial issue of 1');

    // Now issue remaining items: 1 more spare part, 2 consumables, and checkout the tool
    const completeIssue = await api(`/requests/${requestId}/issue`, {
      method: 'POST',
      role: 'STOREKEEPER',
      name: 'Storekeeper John',
      body: {
        receivedBy: 'Kamau Tech',
        lines: [
          { lineId: partLine.id, quantity: 1 },
          { lineId: consLine.id, quantity: 2 },
          { lineId: toolLine.id, quantity: 1 },
        ],
      },
    });
    assert(completeIssue.status === 200 && completeIssue.data.status === 'ISSUED', 'Request fully transitioned to ISSUED');

    const partFinal = await prisma.partCatalog.findUnique({ where: { id: sparePart.id } });
    const consFinal = await prisma.inventoryItem.findUnique({ where: { id: consumable.id } });
    const toolFinal = await prisma.toolAsset.findUnique({ where: { id: toolAsset.id } });
    assert(partFinal!.stockQuantity === 8, 'Spare part stock decremented to 8 (2 total issued)');
    assert(consFinal!.quantityOnHand === 18, 'Consumable stock decremented to 18 (2 boxes issued)');
    assert(toolFinal!.status === 'CHECKED_OUT' && toolFinal!.assignedTo === 'Kamau Tech', 'Tool marked CHECKED_OUT to Kamau Tech');

    // -------------------------------------------------------------
    // Test 7: Technician Acknowledgement of Receipt
    // -------------------------------------------------------------
    console.log('\n--- Test 7: Technician Physical Receipt Acknowledgement ---');
    
    const ackRes = await api(`/requests/${requestId}/acknowledge`, {
      method: 'POST',
      role: 'MECHANIC',
      name: 'Kamau Tech',
      body: { notes: 'All parts, consumables, and OBD tool received in good order' },
    });
    assert(ackRes.status === 200 && ackRes.data.acknowledgedBy === 'Kamau Tech', 'Technician successfully confirmed receipt');

    // -------------------------------------------------------------
    // Test 8: Job Costing and Vehicle Expense Linkage
    // -------------------------------------------------------------
    console.log('\n--- Test 8: Job Costing Calculation ---');
    
    const costing = await api(`/jobs/${jobCard.id}/costing`, { role: 'MANAGER' });
    assert(costing.status === 200, 'Job costing retrieved successfully');
    assert(costing.data.lines.length === 1, 'Job costing includes the 1 spare part line issued to this job');
    assert(costing.data.lines[0].qty === 2, 'Quantity linked to job card is 2');
    assert(costing.data.totals.cost === 5000, 'Total cost calculation is 2 * 2500 = 5000 KES');
    assert(costing.data.totals.price === 9000, 'Total customer billing price is 2 * 4500 = 9000 KES');

    // -------------------------------------------------------------
    // Test 9: Returns and Inspection Workflow (Restock vs Quarantine vs Damaged)
    // -------------------------------------------------------------
    console.log('\n--- Test 9: Returns, Inspection & Quarantine ---');
    
    // Technician returns 1 unused brake pad
    const returnReq = await api('/returns', {
      method: 'POST',
      role: 'MECHANIC',
      name: 'Kamau Tech',
      body: {
        requestLineId: partLine.id,
        quantity: 1,
        condition: 'UNOPENED_NEW',
        notes: 'Only 1 pad set needed for front axle, returning unopened 2nd set',
      },
    });
    assert(returnReq.status === 200 && returnReq.data.status === 'PENDING_INSPECTION', 'Returned part in PENDING_INSPECTION');
    
    // Stock quantity is NOT yet available, it is safely in quarantineQuantity
    const partInQuarantine = await prisma.partCatalog.findUnique({ where: { id: sparePart.id } });
    assert(partInQuarantine!.stockQuantity === 8, 'Available stock remains 8 prior to inspection');
    assert(partInQuarantine!.quarantineQuantity === 1, 'Quarantine quantity holds 1 returned part awaiting QC');

    // Storekeeper inspects and RESTOCKS
    const inspectRes = await api(`/returns/${returnReq.data.id}/inspect`, {
      method: 'POST',
      role: 'STOREKEEPER',
      name: 'Storekeeper John',
      body: { outcome: 'RESTOCK', notes: 'Inspected and verified original sealed packaging' },
    });
    assert(inspectRes.status === 200 && inspectRes.data.status === 'RESTOCKED', 'Return marked as RESTOCKED');

    const partAfterRestock = await prisma.partCatalog.findUnique({ where: { id: sparePart.id } });
    assert(partAfterRestock!.stockQuantity === 9, 'Available stock restored back to 9');
    assert(partAfterRestock!.quarantineQuantity === 0, 'Quarantine cleared back to 0');

    // Recheck job costing: now net quantity on job is 1!
    const costingAfterReturn = await api(`/jobs/${jobCard.id}/costing`, { role: 'MANAGER' });
    assert(costingAfterReturn.data.lines[0].qty === 1, 'Job costing adjusted to net 1 part after restock return');
    assert(costingAfterReturn.data.totals.price === 4500, 'Customer billing price reduced to 4500 KES');

    // Return Tool Asset
    const returnTool = await api('/returns', {
      method: 'POST',
      role: 'MECHANIC',
      name: 'Kamau Tech',
      body: {
        requestLineId: toolLine.id,
        condition: 'GOOD',
        notes: 'Diagnostic scanning complete, returning unit',
      },
    });
    await api(`/returns/${returnTool.data.id}/inspect`, {
      method: 'POST',
      role: 'STOREKEEPER',
      body: { outcome: 'RESTOCK', condition: 'GOOD', notes: 'Scanner checked and battery charged' },
    });
    const toolReturned = await prisma.toolAsset.findUnique({ where: { id: toolAsset.id } });
    assert(toolReturned!.status === 'AVAILABLE', 'Diagnostic scanner returned to AVAILABLE status');

    // -------------------------------------------------------------
    // Test 10: Damaged Equipment Reporting
    // -------------------------------------------------------------
    console.log('\n--- Test 10: Damaged Equipment Reporting ---');
    
    // Check out tool again, then report damaged
    await api(`/assets/${toolAsset.id}/checkout`, {
      method: 'POST',
      role: 'STOREKEEPER',
      body: { employee: 'Peter Tech', reason: 'Field diagnosis' },
    });
    const damageReport = await api(`/assets/${toolAsset.id}/report`, {
      method: 'POST',
      role: 'MECHANIC',
      name: 'Peter Tech',
      body: { kind: 'DAMAGED', reason: 'Cable connector bent during testing' },
    });
    assert(damageReport.status === 200 && damageReport.data.status === 'DAMAGED', 'Asset marked DAMAGED');

    // -------------------------------------------------------------
    // Test 11: Stock Count & Stocktake Variance Approval
    // -------------------------------------------------------------
    console.log('\n--- Test 11: Stocktake Variance Approval ---');
    
    // Physical count of consumable finds 19 boxes (recorded 18, surplus of +1)
    const stockCount = await api('/stockcounts', {
      method: 'POST',
      role: 'STOREKEEPER',
      name: 'Storekeeper John',
      body: {
        category: 'CONSUMABLE',
        itemId: consumable.id,
        countedQty: 19,
        notes: 'Found extra sealed box in lower cabinet',
      },
    });
    assert(stockCount.status === 200 && stockCount.data.variance === 1, 'Stock count recorded +1 variance');

    // Inventory Manager approves stock count
    const approveCount = await api(`/stockcounts/${stockCount.data.id}/approve`, {
      method: 'POST',
      role: 'INVENTORY_MANAGER',
      name: 'Grace Inventory Mgr',
      body: { approve: true },
    });
    assert(approveCount.status === 200 && approveCount.data.status === 'APPROVED', 'Stock count approved');

    const consAfterStocktake = await prisma.inventoryItem.findUnique({ where: { id: consumable.id } });
    assert(consAfterStocktake!.quantityOnHand === 19, 'Consumable stock adjusted to physical count of 19');

    // -------------------------------------------------------------
    // Test 12: Immutable Audit Ledger Verification
    // -------------------------------------------------------------
    console.log('\n--- Test 12: Immutable Audit Ledger Verification ---');
    
    const txAudit = await api('/transactions?limit=10', { role: 'MANAGER' });
    assert(txAudit.status === 200 && txAudit.data.length > 0, 'Transactions audit trail retrieved');
    const firstTx = txAudit.data[0];

    // Attempting direct SQL UPDATE or DELETE on InventoryTransaction should fail due to trigger!
    let updateFailed = false;
    try {
      await prisma.$executeRawUnsafe(`UPDATE "InventoryTransaction" SET notes = 'tampered' WHERE id = '${firstTx.id}'`);
    } catch (e: any) {
      updateFailed = true;
      assert(e.message.includes('append-only'), 'Database trigger blocked UPDATE on InventoryTransaction (immutable)');
    }
    assert(updateFailed, 'Immutability constraint verified on audit ledger');

    // -------------------------------------------------------------
    // Test 13: Summary Reports & CSV Export
    // -------------------------------------------------------------
    console.log('\n--- Test 13: Summary Reports & CSV Export ---');
    
    const summary = await api('/reports/summary', { role: 'MANAGER' });
    assert(summary.status === 200, 'Summary reports compiled');
    assert(summary.data.balances.length >= 3, 'Reports include all inventory category balances');
    assert(summary.data.valuation.total > 0, 'Inventory valuation calculated');

    const csvRes = await fetch(`${baseUrl}/reports/export?report=transactions`, {
      headers: { 'x-user-role': 'MANAGER', 'x-user-name': 'Manager' },
    });
    const csvText = await csvRes.text();
    assert(csvRes.status === 200 && csvText.startsWith('id,tenantId,reference'), 'CSV export generated successfully');

    console.log('\n🎉 ALL WORKSHOP INVENTORY TESTS PASSED WITH 100% SUCCESS!');
  } finally {
    server.close();
    await prisma.$disconnect();
  }
}

runTests().catch((err) => {
  console.error('\n❌ TEST RUN FAILED:', err);
  process.exit(1);
});
