import { Router, Request, Response } from 'express';
import { PrismaClient, Prisma, InventoryCategory } from '@prisma/client';

/**
 * Workshop Inventory module.
 *
 *  - SPARE_PART     -> PartCatalog / StockMovement (existing tables, reused)
 *  - CONSUMABLE     -> InventoryItem (internal supplies, never sold)
 *  - TOOL_EQUIPMENT -> ToolAsset (one row per physical asset)
 *
 * Approval and physical issuance are separate steps: stock only moves on ISSUE.
 * Every change appends an InventoryTransaction row (immutable, DB trigger enforced).
 * Every query is scoped by tenantId taken from the acting user.
 */

type Tx = Prisma.TransactionClient;

export interface Actor {
  id?: string;
  name: string;
  role: string;
  tenantId: string;
}

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

const ADMINS = ['SUPER_ADMIN', 'OWNER', 'ADMIN'];

export const INVENTORY_PERMS: Record<string, string[]> = {
  'request:create': ['MECHANIC', 'INSPECTOR', ...ADMINS],
  'request:viewAll': ['STOREKEEPER', 'INVENTORY_MANAGER', 'MANAGER', 'ACCOUNTS', ...ADMINS],
  'request:decide': ['STOREKEEPER', 'INVENTORY_MANAGER', 'MANAGER', ...ADMINS],
  'request:decideExceptional': ['MANAGER', ...ADMINS],
  'stock:issue': ['STOREKEEPER', 'INVENTORY_MANAGER', ...ADMINS],
  'return:create': ['MECHANIC', 'INSPECTOR', 'STOREKEEPER', 'INVENTORY_MANAGER', ...ADMINS],
  'return:inspect': ['STOREKEEPER', 'INVENTORY_MANAGER', ...ADMINS],
  'catalog:manage': ['STOREKEEPER', 'INVENTORY_MANAGER', ...ADMINS],
  'catalog:view': ['MECHANIC', 'INSPECTOR', 'STOREKEEPER', 'INVENTORY_MANAGER', 'MANAGER', 'ACCOUNTS', ...ADMINS],
  'stock:adjust': ['INVENTORY_MANAGER', ...ADMINS],
  'stock:writeoff': ['MANAGER', ...ADMINS],
  'stocktake:count': ['STOREKEEPER', 'INVENTORY_MANAGER', ...ADMINS],
  'stocktake:approve': ['INVENTORY_MANAGER', 'MANAGER', ...ADMINS],
  'report:view': ['STOREKEEPER', 'INVENTORY_MANAGER', 'MANAGER', 'ACCOUNTS', ...ADMINS],
  'report:cost': ['INVENTORY_MANAGER', 'MANAGER', 'ACCOUNTS', ...ADMINS],
  'job:costing': ['ADVISOR', 'STOREKEEPER', 'INVENTORY_MANAGER', 'MANAGER', 'ACCOUNTS', ...ADMINS],
  'notification:view': ['STOREKEEPER', 'INVENTORY_MANAGER', 'MANAGER', ...ADMINS],
};

const ALL_ROLES = new Set([
  'SUPER_ADMIN', 'OWNER', 'ADMIN', 'MANAGER', 'ADVISOR', 'ACCOUNTS', 'CASHIER',
  'STOREKEEPER', 'INSPECTOR', 'MECHANIC', 'INVENTORY_MANAGER',
]);

const EXCEPTIONAL_LIMIT = Number(process.env.INVENTORY_EXCEPTIONAL_LIMIT) || 20000;
const CATEGORIES: InventoryCategory[] = ['SPARE_PART', 'TOOL_EQUIPMENT', 'CONSUMABLE'];

const ref = (prefix: string) =>
  `${prefix}-${Date.now().toString(36).toUpperCase()}${Math.random().toString(36).slice(2, 5).toUpperCase()}`;

function can(actor: Actor, perm: string): boolean {
  return (INVENTORY_PERMS[perm] || []).includes(actor.role);
}

function require_(actor: Actor, perm: string, action: string) {
  if (!can(actor, perm)) {
    throw new HttpError(403, `Role ${actor.role} is not allowed to ${action}`);
  }
}

function posInt(v: any, name: string, min = 1): number {
  const n = Number(v);
  if (!Number.isInteger(n) || n < min) throw new HttpError(400, `${name} must be a whole number >= ${min}`);
  return n;
}

function cat(v: any): InventoryCategory {
  if (!CATEGORIES.includes(v)) throw new HttpError(400, `category must be one of ${CATEGORIES.join(', ')}`);
  return v as InventoryCategory;
}

function text(v: any): string | undefined {
  return v === undefined || v === null || String(v).trim() === '' ? undefined : String(v).trim();
}

export function createInventoryRouter(
  prisma: PrismaClient,
  getDefaultTenantId: () => Promise<string>
): Router {
  const router = Router();

  // ---------------------------------------------------------------
  // Identity: x-user-id (preferred, tenant + role come from the DB) or
  // x-user-role / x-user-name (legacy UI, active tenant).
  // NOTE: the app has no login yet, so these headers are trusted.
  // ---------------------------------------------------------------
  async function resolveActor(req: Request): Promise<Actor> {
    const uid = req.header('x-user-id');
    if (uid) {
      const u = await prisma.user.findUnique({ where: { id: uid } });
      if (!u) throw new HttpError(401, 'Unknown user');
      return { id: u.id, name: u.name, role: u.role, tenantId: u.tenantId };
    }
    const role = (req.header('x-user-role') || String(req.query.role || '')).toUpperCase();
    if (!ALL_ROLES.has(role)) throw new HttpError(401, 'Missing or invalid x-user-role');
    return {
      name: req.header('x-user-name') || String(req.query.userName || role),
      role,
      tenantId: await getDefaultTenantId(),
    };
  }

  function route(fn: (a: Actor, req: Request, res: Response) => Promise<any>) {
    return async (req: Request, res: Response) => {
      try {
        const actor = await resolveActor(req);
        const out = await fn(actor, req, res);
        if (!res.headersSent) res.json(out);
      } catch (e: any) {
        if (e instanceof HttpError) return res.status(e.status).json({ error: e.message });
        console.error('Inventory error:', e);
        res.status(500).json({ error: 'Inventory operation failed' });
      }
    };
  }

  const txn = <T>(fn: (tx: Tx) => Promise<T>) =>
    prisma.$transaction(fn, { maxWait: 10000, timeout: 20000 });

  async function ledger(tx: Tx, a: Actor, data: Omit<Prisma.InventoryTransactionUncheckedCreateInput, 'tenantId' | 'reference' | 'actorName' | 'actorRole'>) {
    return tx.inventoryTransaction.create({
      data: { tenantId: a.tenantId, reference: ref('TXN'), actorId: a.id, actorName: a.name, actorRole: a.role, ...data },
    });
  }

  // ---------------- item helpers ----------------
  interface ItemInfo { name: string; cost: number; price?: number; available: number; location: string; partId?: string; inventoryItemId?: string; toolAssetId?: string }

  async function itemInfo(tx: Tx, tenantId: string, c: InventoryCategory, id: string): Promise<ItemInfo> {
    if (c === 'SPARE_PART') {
      const p = await tx.partCatalog.findFirst({ where: { id, tenantId } });
      if (!p) throw new HttpError(404, 'Spare part not found');
      return { name: `${p.description} (${p.partNumber})`, cost: p.costPrice, price: p.unitPrice, available: p.stockQuantity, location: p.location, partId: p.id };
    }
    if (c === 'CONSUMABLE') {
      const i = await tx.inventoryItem.findFirst({ where: { id, tenantId } });
      if (!i) throw new HttpError(404, 'Consumable item not found');
      return { name: i.name, cost: i.unitCost, available: i.quantityOnHand, location: i.location, inventoryItemId: i.id };
    }
    const t = await tx.toolAsset.findFirst({ where: { id, tenantId } });
    if (!t) throw new HttpError(404, 'Tool / equipment asset not found');
    return { name: `${t.name} (${t.assetNumber})`, cost: t.cost, available: t.status === 'AVAILABLE' ? 1 : 0, location: t.location, toolAssetId: t.id };
  }

  const lockRow = (tx: Tx, table: string, id: string, tenantId: string) =>
    tx.$queryRawUnsafe(`SELECT id FROM "${table}" WHERE id = $1 AND "tenantId" = $2 FOR UPDATE`, id, tenantId);

  // Atomic stock change; never lets a balance go below zero.
  async function moveStock(tx: Tx, tenantId: string, c: InventoryCategory, id: string, delta: number, field: 'available' | 'quarantine' = 'available') {
    if (c === 'SPARE_PART') {
      const col = field === 'available' ? 'stockQuantity' : 'quarantineQuantity';
      const n = await tx.partCatalog.updateMany({
        where: { id, tenantId, ...(delta < 0 ? { [col]: { gte: -delta } } : {}) },
        data: { [col]: delta < 0 ? { decrement: -delta } : { increment: delta } },
      });
      if (n.count !== 1) throw new HttpError(409, 'Insufficient stock');
    } else if (c === 'CONSUMABLE') {
      const col = field === 'available' ? 'quantityOnHand' : 'quarantineQuantity';
      const n = await tx.inventoryItem.updateMany({
        where: { id, tenantId, ...(delta < 0 ? { [col]: { gte: -delta } } : {}) },
        data: { [col]: delta < 0 ? { decrement: -delta } : { increment: delta } },
      });
      if (n.count !== 1) throw new HttpError(409, 'Insufficient stock');
    } else {
      throw new HttpError(400, 'Tools are tracked per asset, not by quantity');
    }
  }

  function lineRef(l: { category: InventoryCategory; partId: string | null; inventoryItemId: string | null; toolAssetId: string | null }) {
    return { category: l.category, partId: l.partId, inventoryItemId: l.inventoryItemId, toolAssetId: l.toolAssetId };
  }

  async function partMovement(tx: Tx, a: Actor, partId: string, type: string, qty: number, info: ItemInfo, jobCardId: string | null | undefined, notes: string) {
    await tx.stockMovement.create({
      data: { partId, type, quantity: qty, unitCost: info.cost, unitPrice: info.price, jobCardId: jobCardId || null, reference: ref('INV'), notes, tenantId: a.tenantId },
    });
  }

  // =====================================================================
  // CATALOGUE (search) - used by technician mobile app and storekeeper UI
  // =====================================================================
  router.get('/catalog', route(async (a, req) => {
    require_(a, 'catalog:view', 'search the inventory');
    const q = String(req.query.q || '').trim();
    const only = req.query.category ? cat(req.query.category) : undefined;
    const like = q ? { contains: q, mode: 'insensitive' as const } : undefined;
    const out: any[] = [];
    if (!only || only === 'SPARE_PART') {
      const parts = await prisma.partCatalog.findMany({
        where: { tenantId: a.tenantId, ...(like ? { OR: [{ description: like }, { partNumber: like }, { brand: like }] } : {}) },
        take: 50, orderBy: { description: 'asc' },
      });
      out.push(...parts.map((p) => ({ category: 'SPARE_PART', id: p.id, name: p.description, code: p.partNumber, available: p.stockQuantity, location: p.location })));
    }
    if (!only || only === 'CONSUMABLE') {
      const items = await prisma.inventoryItem.findMany({
        where: { tenantId: a.tenantId, ...(like ? { OR: [{ name: like }, { sku: like }] } : {}) },
        take: 50, orderBy: { name: 'asc' },
      });
      out.push(...items.map((i) => ({ category: 'CONSUMABLE', id: i.id, name: i.name, code: i.sku, unit: i.unit, available: i.quantityOnHand, location: i.location })));
    }
    if (!only || only === 'TOOL_EQUIPMENT') {
      const tools = await prisma.toolAsset.findMany({
        where: { tenantId: a.tenantId, status: { notIn: ['WRITTEN_OFF'] }, ...(like ? { OR: [{ name: like }, { assetNumber: like }, { serialNumber: like }] } : {}) },
        take: 50, orderBy: { name: 'asc' },
      });
      out.push(...tools.map((t) => ({ category: 'TOOL_EQUIPMENT', id: t.id, name: t.name, code: t.assetNumber, available: t.status === 'AVAILABLE' ? 1 : 0, status: t.status, location: t.location })));
    }
    return out;
  }));

  // =====================================================================
  // CATALOGUE MANAGEMENT: consumables, tool assets, receiving stock
  // =====================================================================
  router.post('/items', route(async (a, req) => {
    require_(a, 'catalog:manage', 'manage the item catalogue');
    const { sku, name, unit, reorderLevel, unitCost, location, supplierName, quantity } = req.body;
    if (!text(sku) || !text(name)) throw new HttpError(400, 'sku and name are required');
    const qty = quantity === undefined ? 0 : posInt(quantity, 'quantity', 0);
    return txn(async (tx) => {
      const dup = await tx.inventoryItem.findFirst({ where: { tenantId: a.tenantId, sku: String(sku) } });
      if (dup) throw new HttpError(409, 'SKU already exists');
      const item = await tx.inventoryItem.create({
        data: {
          tenantId: a.tenantId, sku: String(sku).trim(), name: String(name).trim(), unit: text(unit) || 'pcs',
          reorderLevel: reorderLevel === undefined ? 5 : posInt(reorderLevel, 'reorderLevel', 0),
          unitCost: Number(unitCost) || 0, location: text(location) || 'Main Store', supplierName: text(supplierName), quantityOnHand: qty,
        },
      });
      if (qty > 0) {
        await ledger(tx, a, { type: 'RECEIVE', category: 'CONSUMABLE', inventoryItemId: item.id, itemName: item.name, quantity: qty, quantityDetail: qty, unitCost: item.unitCost, location: item.location, reason: 'Opening stock' });
      }
      return item;
    });
  }));

  router.get('/items', route(async (a) => {
    require_(a, 'catalog:view', 'view consumables');
    return prisma.inventoryItem.findMany({ where: { tenantId: a.tenantId }, orderBy: { name: 'asc' } });
  }));

  router.post('/assets', route(async (a, req) => {
    require_(a, 'catalog:manage', 'register company assets');
    const { assetNumber, name, serialNumber, purchaseDate, cost, condition, isFixed, location, assignedTo, department } = req.body;
    if (!text(assetNumber) || !text(name)) throw new HttpError(400, 'assetNumber and name are required');
    return txn(async (tx) => {
      const dup = await tx.toolAsset.findFirst({ where: { tenantId: a.tenantId, assetNumber: String(assetNumber) } });
      if (dup) throw new HttpError(409, 'Asset number already exists');
      const fixed = Boolean(isFixed);
      const asset = await tx.toolAsset.create({
        data: {
          tenantId: a.tenantId, assetNumber: String(assetNumber).trim(), name: String(name).trim(), serialNumber: text(serialNumber),
          purchaseDate: purchaseDate ? new Date(purchaseDate) : null, cost: Number(cost) || 0, condition: text(condition) || 'GOOD',
          isFixed: fixed, status: fixed ? 'FIXED' : 'AVAILABLE', location: text(location) || 'Main Store',
          assignedTo: text(assignedTo), department: text(department),
        },
      });
      await ledger(tx, a, { type: 'RECEIVE', category: 'TOOL_EQUIPMENT', toolAssetId: asset.id, itemName: asset.name, quantity: 1, quantityDetail: 1, unitCost: asset.cost, location: asset.location, condition: asset.condition, reason: 'Asset registered' });
      return asset;
    });
  }));

  router.get('/assets', route(async (a, req) => {
    require_(a, 'catalog:view', 'view assets');
    const status = text(req.query.status);
    return prisma.toolAsset.findMany({ where: { tenantId: a.tenantId, ...(status ? { status } : {}) }, orderBy: { assetNumber: 'asc' } });
  }));

  // Assign fixed / permanent equipment to a workshop, department or location (no checkout needed).
  router.post('/assets/:id/assign', route(async (a, req) => {
    require_(a, 'catalog:manage', 'assign equipment');
    const { location, assignedTo, department, isFixed } = req.body;
    if (!text(location) && !text(assignedTo) && !text(department)) throw new HttpError(400, 'Provide location, assignedTo or department');
    return txn(async (tx) => {
      await lockRow(tx, 'ToolAsset', String(req.params.id), a.tenantId);
      const asset = await tx.toolAsset.findFirst({ where: { id: String(req.params.id), tenantId: a.tenantId } });
      if (!asset) throw new HttpError(404, 'Asset not found');
      if (asset.status === 'CHECKED_OUT') throw new HttpError(409, 'Asset is checked out; return it first');
      if (['LOST', 'WRITTEN_OFF'].includes(asset.status)) throw new HttpError(409, `Asset is ${asset.status}`);
      const fixed = isFixed === undefined ? asset.isFixed : Boolean(isFixed);
      const updated = await tx.toolAsset.update({
        where: { id: asset.id },
        data: { location: text(location) || asset.location, assignedTo: text(assignedTo) ?? asset.assignedTo, department: text(department) ?? asset.department, isFixed: fixed, status: fixed ? 'FIXED' : asset.status === 'FIXED' ? 'AVAILABLE' : asset.status },
      });
      await ledger(tx, a, { type: 'ASSIGN', category: 'TOOL_EQUIPMENT', toolAssetId: asset.id, itemName: asset.name, location: updated.location, department: updated.department, recipientName: updated.assignedTo, reason: text(req.body.reason) || 'Assignment updated' });
      return updated;
    });
  }));

  // Walk-up checkout without a technician request (storekeeper records it).
  router.post('/assets/:id/checkout', route(async (a, req) => {
    require_(a, 'stock:issue', 'check out equipment');
    const employee = text(req.body.employee);
    if (!employee) throw new HttpError(400, 'employee is required');
    const expected = req.body.expectedReturnAt ? new Date(req.body.expectedReturnAt) : null;
    return txn(async (tx) => {
      const asset = await tx.toolAsset.findFirst({ where: { id: String(req.params.id), tenantId: a.tenantId } });
      if (!asset) throw new HttpError(404, 'Asset not found');
      if (asset.isFixed) throw new HttpError(409, 'Fixed equipment is assigned, not checked out');
      const n = await tx.toolAsset.updateMany({
        where: { id: asset.id, tenantId: a.tenantId, status: 'AVAILABLE' },
        data: { status: 'CHECKED_OUT', assignedTo: employee, usedAt: text(req.body.usedAt) || null, checkedOutAt: new Date(), expectedReturnAt: expected },
      });
      if (n.count !== 1) throw new HttpError(409, `Asset is not available (${asset.status})`);
      await ledger(tx, a, { type: 'ISSUE', category: 'TOOL_EQUIPMENT', toolAssetId: asset.id, itemName: asset.name, quantity: -1, quantityDetail: 1, recipientName: employee, location: text(req.body.usedAt), reason: text(req.body.reason) || 'Equipment checkout', condition: asset.condition });
      return tx.toolAsset.findUnique({ where: { id: asset.id } });
    });
  }));

  // Loss / damage / write-off of an asset.
  router.post('/assets/:id/report', route(async (a, req) => {
    const kind = String(req.body.kind || '').toUpperCase();
    const reason = text(req.body.reason);
    if (!['LOST', 'DAMAGED', 'WRITE_OFF'].includes(kind)) throw new HttpError(400, 'kind must be LOST, DAMAGED or WRITE_OFF');
    if (!reason) throw new HttpError(400, 'reason is required');
    if (kind === 'WRITE_OFF') require_(a, 'stock:writeoff', 'write off or dispose of equipment');
    else require_(a, 'return:create', 'report lost or damaged equipment');
    return txn(async (tx) => {
      await lockRow(tx, 'ToolAsset', String(req.params.id), a.tenantId);
      const asset = await tx.toolAsset.findFirst({ where: { id: String(req.params.id), tenantId: a.tenantId } });
      if (!asset) throw new HttpError(404, 'Asset not found');
      if (asset.status === 'WRITTEN_OFF') throw new HttpError(409, 'Asset already written off');
      const status = kind === 'WRITE_OFF' ? 'WRITTEN_OFF' : kind;
      const wasAvailable = asset.status === 'AVAILABLE';
      const updated = await tx.toolAsset.update({ where: { id: asset.id }, data: { status, condition: kind === 'DAMAGED' ? 'DAMAGED' : asset.condition } });
      await ledger(tx, a, { type: kind === 'WRITE_OFF' ? 'WRITE_OFF' : kind, category: 'TOOL_EQUIPMENT', toolAssetId: asset.id, itemName: asset.name, quantity: wasAvailable ? -1 : 0, quantityDetail: 1, unitCost: asset.cost, recipientName: asset.assignedTo, reason, notes: text(req.body.notes), condition: updated.condition });
      return updated;
    });
  }));

  router.post('/receive', route(async (a, req) => {
    require_(a, 'catalog:manage', 'receive stock');
    const c = cat(req.body.category);
    if (c === 'TOOL_EQUIPMENT') throw new HttpError(400, 'Register tools via /assets');
    const qty = posInt(req.body.quantity, 'quantity');
    const itemId = String(req.body.itemId || '');
    return txn(async (tx) => {
      const info = await itemInfo(tx, a.tenantId, c, itemId);
      const unitCost = req.body.unitCost !== undefined ? Number(req.body.unitCost) : info.cost;
      if (!(unitCost >= 0)) throw new HttpError(400, 'unitCost must be >= 0');
      await moveStock(tx, a.tenantId, c, itemId, qty);
      if (c === 'SPARE_PART') {
        await tx.partCatalog.update({ where: { id: itemId }, data: { costPrice: unitCost, ...(text(req.body.supplierName) ? { supplierName: text(req.body.supplierName) } : {}) } });
        await partMovement(tx, a, itemId, 'RECEIVED', qty, { ...info, cost: unitCost }, null, text(req.body.notes) || 'Stock received');
      } else {
        await tx.inventoryItem.update({ where: { id: itemId }, data: { unitCost } });
      }
      return ledger(tx, a, { type: 'RECEIVE', category: c, partId: info.partId, inventoryItemId: info.inventoryItemId, itemName: info.name, quantity: qty, quantityDetail: qty, unitCost, location: info.location, reason: text(req.body.reference) || 'Stock received', notes: text(req.body.notes) });
    });
  }));

  // Direct dispatch of workshop consumables (walk-up issue to an individual person or department)
  router.post('/consume', route(async (a, req) => {
    require_(a, 'stock:issue', 'issue operational consumables');
    const { itemId, quantity, department, issuedTo, purpose, notes, destinationType, unpackFromBox, piecesPerBox } = req.body;
    if (!text(itemId)) throw new HttpError(400, 'itemId is required');
    const qty = posInt(quantity, 'quantity');
    const isIndividual = destinationType === 'INDIVIDUAL' || !text(department) || department === 'Individual Issue';
    const dept = isIndividual ? 'Individual Issue' : (text(department) || 'Workshop');
    const recipient = text(issuedTo) || (isIndividual ? 'Technician' : dept);
    const reason = text(purpose) || (isIndividual ? `Personal issue to ${recipient}` : `Operational supplies for ${dept}`);

    return txn(async (tx) => {
      const existing = await tx.inventoryItem.findFirst({ where: { id: String(itemId), tenantId: a.tenantId } });
      if (!existing) throw new HttpError(404, 'Consumable item not found');

      let unitCost = existing.unitCost;
      let finalItem = existing;

      // If item was stored in boxes/packs and storekeeper is issuing loose pieces:
      if (Boolean(unpackFromBox) && piecesPerBox && Number(piecesPerBox) > 1 && ['box', 'pack', 'packet', 'drum'].includes(existing.unit.toLowerCase())) {
        const factor = posInt(piecesPerBox, 'piecesPerBox');
        const totalPieces = existing.quantityOnHand * factor;
        if (qty > totalPieces) throw new HttpError(409, `Only ${totalPieces} pieces available in stock`);
        unitCost = Number((existing.unitCost / factor).toFixed(2));
        finalItem = await tx.inventoryItem.update({
          where: { id: existing.id },
          data: {
            unit: 'pcs',
            quantityOnHand: totalPieces - qty,
            unitCost,
          },
        });
      } else {
        if (qty > existing.quantityOnHand) throw new HttpError(409, `Only ${existing.quantityOnHand} ${existing.unit} available in stock`);
        await moveStock(tx, a.tenantId, 'CONSUMABLE', String(itemId), -qty);
        finalItem = (await tx.inventoryItem.findUnique({ where: { id: String(itemId) } }))!;
      }

      const entry = await ledger(tx, a, {
        type: 'ISSUE',
        category: 'CONSUMABLE',
        inventoryItemId: String(itemId),
        itemName: finalItem.name,
        quantity: -qty,
        quantityDetail: qty,
        unitCost,
        department: dept,
        recipientName: recipient,
        reason,
        notes: text(notes) || (isIndividual ? `Direct personal issue to ${recipient}` : undefined),
        location: finalItem.location,
      });

      return { item: finalItem, transaction: entry };
    });
  }));

  // =====================================================================
  // 1. TECHNICIAN REQUESTS
  // =====================================================================
  router.post('/requests', route(async (a, req) => {
    require_(a, 'request:create', 'request items');
    const { jobCardId, vehicleId, department, reason, lines } = req.body;
    if (!text(reason)) throw new HttpError(400, 'reason is required');
    if (!Array.isArray(lines) || lines.length === 0) throw new HttpError(400, 'At least one line is required');
    if (lines.length > 50) throw new HttpError(400, 'Too many lines');

    const technicianName = ADMINS.includes(a.role) && text(req.body.technicianName) ? String(req.body.technicianName) : a.name;

    return txn(async (tx) => {
      let veh = text(vehicleId);
      let job = text(jobCardId);
      let jobNo: string | undefined;
      if (job) {
        const j = await tx.jobCard.findFirst({ where: { id: job, tenantId: a.tenantId } });
        if (!j) throw new HttpError(404, 'Job card not found');
        job = j.id; jobNo = j.jobNumber || undefined;
        if (!veh) veh = j.vehicleId;
      }
      if (veh) {
        const v = await tx.vehicle.findFirst({ where: { id: veh, customer: { tenantId: a.tenantId } } });
        if (!v) throw new HttpError(404, 'Vehicle not found');
      }

      const built: Prisma.ItemRequestLineUncheckedCreateWithoutRequestInput[] = [];
      for (const l of lines) {
        const c = cat(l.category);
        const qty = posInt(l.quantity, 'quantity');
        if (c === 'TOOL_EQUIPMENT' && qty !== 1) throw new HttpError(400, 'Tool requests must be for exactly 1 asset');
        const info = await itemInfo(tx, a.tenantId, c, String(l.itemId || ''));
        if (c === 'SPARE_PART' && !job) throw new HttpError(400, 'Spare parts must be requested against a job card');
        built.push({
          tenantId: a.tenantId, category: c, partId: info.partId, inventoryItemId: info.inventoryItemId, toolAssetId: info.toolAssetId,
          description: info.name, qtyRequested: qty, expectedReturnAt: l.expectedReturnAt ? new Date(l.expectedReturnAt) : null,
        });
      }

      const request = await tx.itemRequest.create({
        data: {
          tenantId: a.tenantId, reference: ref('REQ'), technicianId: a.id, technicianName, jobCardId: job, vehicleId: veh,
          department: text(department) || 'Workshop', reason: String(reason).trim(), lines: { create: built },
        },
        include: { lines: true },
      });
      for (const l of request.lines) {
        await ledger(tx, a, { type: 'REQUEST', category: l.category, partId: l.partId, inventoryItemId: l.inventoryItemId, toolAssetId: l.toolAssetId, itemName: l.description, requestId: request.id, requestLineId: l.id, jobCardId: job, vehicleId: veh, department: request.department, quantityDetail: l.qtyRequested, recipientName: technicianName, reason: request.reason });
      }
      await tx.storeNotification.create({
        data: { tenantId: a.tenantId, targetRole: 'STOREKEEPER', type: 'NEW_REQUEST', requestId: request.id, message: `${technicianName} requested ${request.lines.length} item(s)${jobNo ? ` for ${jobNo}` : ''} (${request.reference})` },
      });
      return request;
    });
  }));

  async function loadRequest(tenantId: string, id: string, client: Tx | PrismaClient = prisma) {
    const r = await client.itemRequest.findFirst({ where: { id, tenantId }, include: { lines: true } });
    if (!r) throw new HttpError(404, 'Request not found');
    return r;
  }

  function assertVisible(a: Actor, r: { technicianName: string; technicianId: string | null }) {
    if (can(a, 'request:viewAll')) return;
    if (r.technicianName === a.name || (a.id && r.technicianId === a.id)) return;
    throw new HttpError(403, 'You can only access your own requests');
  }

  router.get('/requests', route(async (a, req) => {
    const viewAll = can(a, 'request:viewAll');
    if (!viewAll && !can(a, 'request:create')) throw new HttpError(403, `Role ${a.role} is not allowed to view requests`);
    const status = text(req.query.status);
    const where: Prisma.ItemRequestWhereInput = { tenantId: a.tenantId, ...(status ? { status } : {}) };
    if (!viewAll || req.query.mine === '1') where.technicianName = a.name;
    else if (text(req.query.technician)) where.technicianName = String(req.query.technician);
    if (text(req.query.jobCardId)) where.jobCardId = String(req.query.jobCardId);
    return prisma.itemRequest.findMany({ where, include: { lines: true }, orderBy: { createdAt: 'desc' }, take: 200 });
  }));

  router.get('/requests/:id', route(async (a, req) => {
    const r = await loadRequest(a.tenantId, String(req.params.id));
    assertVisible(a, r);
    const history = await prisma.inventoryTransaction.findMany({ where: { tenantId: a.tenantId, requestId: r.id }, orderBy: { createdAt: 'asc' } });
    const lines = [];
    for (const l of r.lines) {
      let availableNow: number | null = null;
      try {
        const id = l.partId || l.inventoryItemId || l.toolAssetId;
        if (id) availableNow = (await itemInfo(prisma as any, a.tenantId, l.category, id)).available;
      } catch { /* item removed */ }
      lines.push({ ...l, availableNow });
    }
    return { ...r, lines, history };
  }));

  // =====================================================================
  // 2. STOREKEEPER: APPROVE / REJECT / PARTIAL  (no stock movement here)
  // =====================================================================
  router.post('/requests/:id/decision', route(async (a, req) => {
    require_(a, 'request:decide', 'approve or reject requests');
    const action = String(req.body.action || '').toUpperCase();
    if (!['APPROVE', 'REJECT', 'PARTIAL'].includes(action)) throw new HttpError(400, 'action must be APPROVE, REJECT or PARTIAL');
    const notes = text(req.body.notes);
    if (action !== 'APPROVE' && !notes) throw new HttpError(400, 'notes are required when rejecting or partially approving');

    return txn(async (tx) => {
      await lockRow(tx, 'ItemRequest', String(req.params.id), a.tenantId);
      const r = await loadRequest(a.tenantId, String(req.params.id), tx);
      if (r.status !== 'PENDING') throw new HttpError(409, `Request is ${r.status}; only PENDING requests can be decided`);

      const approvals = new Map<string, number>();
      if (action === 'APPROVE') r.lines.forEach((l) => approvals.set(l.id, l.qtyRequested));
      else if (action === 'REJECT') r.lines.forEach((l) => approvals.set(l.id, 0));
      else {
        if (!Array.isArray(req.body.lines)) throw new HttpError(400, 'lines [{lineId, qtyApproved}] required for PARTIAL');
        r.lines.forEach((l) => approvals.set(l.id, 0));
        for (const x of req.body.lines) {
          const line = r.lines.find((l) => l.id === x.lineId);
          if (!line) throw new HttpError(400, `Unknown lineId ${x.lineId}`);
          const q = posInt(x.qtyApproved, 'qtyApproved', 0);
          if (q > line.qtyRequested) throw new HttpError(400, 'qtyApproved cannot exceed qtyRequested');
          approvals.set(line.id, q);
        }
        if (![...approvals.values()].some((q) => q > 0)) throw new HttpError(400, 'Approve at least one item or use REJECT');
      }

      // Exceptional (high value) requests need a manager.
      const exceptional: string[] = [];
      const availability: Record<string, number> = {};
      for (const l of r.lines) {
        const id = (l.partId || l.inventoryItemId || l.toolAssetId)!;
        const info = await itemInfo(tx, a.tenantId, l.category, id);
        availability[l.id] = info.available;
        if ((approvals.get(l.id) || 0) * info.cost > EXCEPTIONAL_LIMIT) exceptional.push(l.description);
      }
      if (exceptional.length && !can(a, 'request:decideExceptional')) {
        throw new HttpError(403, `High-value request (${exceptional.join(', ')}) needs Workshop Manager or Owner approval`);
      }

      const newStatus = action === 'REJECT' ? 'REJECTED' : 'APPROVED';
      for (const l of r.lines) {
        const q = approvals.get(l.id) || 0;
        await tx.itemRequestLine.update({ where: { id: l.id }, data: { qtyApproved: q } });
        await ledger(tx, a, { type: q > 0 ? 'APPROVE' : 'REJECT', category: l.category, partId: l.partId, inventoryItemId: l.inventoryItemId, toolAssetId: l.toolAssetId, itemName: l.description, requestId: r.id, requestLineId: l.id, jobCardId: r.jobCardId, vehicleId: r.vehicleId, department: r.department, quantityDetail: q, recipientName: r.technicianName, reason: notes, notes: `requested ${l.qtyRequested}, available ${availability[l.id]}` });
      }
      await tx.itemRequest.update({ where: { id: r.id }, data: { status: newStatus, decidedBy: a.name, decidedAt: new Date(), decisionNotes: notes } });
      const out = await loadRequest(a.tenantId, r.id, tx);
      return { ...out, availability };
    });
  }));

  router.post('/requests/:id/cancel', route(async (a, req) => {
    return txn(async (tx) => {
      await lockRow(tx, 'ItemRequest', String(req.params.id), a.tenantId);
      const r = await loadRequest(a.tenantId, String(req.params.id), tx);
      const owner = r.technicianName === a.name || (a.id && r.technicianId === a.id);
      if (!owner && !can(a, 'request:decide')) throw new HttpError(403, 'Only the requester or the store can cancel a request');
      if (!['PENDING', 'APPROVED'].includes(r.status)) throw new HttpError(409, `Request is ${r.status} and cannot be cancelled`);
      if (r.lines.some((l) => l.qtyIssued > 0)) throw new HttpError(409, 'Items were already issued; return them instead');
      await tx.itemRequest.update({ where: { id: r.id }, data: { status: 'CANCELLED', decisionNotes: text(req.body.reason) || r.decisionNotes } });
      for (const l of r.lines) {
        await ledger(tx, a, { type: 'CANCEL', category: l.category, partId: l.partId, inventoryItemId: l.inventoryItemId, toolAssetId: l.toolAssetId, itemName: l.description, requestId: r.id, requestLineId: l.id, jobCardId: r.jobCardId, quantityDetail: l.qtyRequested, reason: text(req.body.reason) || 'Cancelled' });
      }
      return loadRequest(a.tenantId, r.id, tx);
    });
  }));

  // =====================================================================
  // 3. PHYSICAL ISSUANCE (this is where stock is deducted)
  // =====================================================================
  router.post('/requests/:id/issue', route(async (a, req) => {
    require_(a, 'stock:issue', 'issue items');
    const body = req.body.lines;
    if (!Array.isArray(body) || body.length === 0) throw new HttpError(400, 'lines [{lineId, quantity}] required');

    return txn(async (tx) => {
      await lockRow(tx, 'ItemRequest', String(req.params.id), a.tenantId);
      const r = await loadRequest(a.tenantId, String(req.params.id), tx);
      if (!['APPROVED', 'PARTIALLY_ISSUED'].includes(r.status)) throw new HttpError(409, `Request is ${r.status}; only approved requests can be issued`);
      const receiver = text(req.body.receivedBy) || r.technicianName;

      // lock lines in a stable order to avoid deadlocks between concurrent issuers
      const wanted = [...body].sort((x: any, y: any) => String(x.lineId).localeCompare(String(y.lineId)));
      const seen = new Set<string>();
      for (const w of wanted) {
        if (seen.has(w.lineId)) throw new HttpError(400, 'Duplicate lineId');
        seen.add(w.lineId);
        const qty = posInt(w.quantity, 'quantity');
        await lockRow(tx, 'ItemRequestLine', String(w.lineId), a.tenantId);
        const line = await tx.itemRequestLine.findFirst({ where: { id: String(w.lineId), requestId: r.id, tenantId: a.tenantId } });
        if (!line) throw new HttpError(400, `Unknown lineId ${w.lineId}`);
        const outstanding = line.qtyApproved - line.qtyIssued;
        if (qty > outstanding) throw new HttpError(409, `Only ${outstanding} approved and not yet issued for "${line.description}"`);
        if (line.category === 'SPARE_PART' && !r.jobCardId) throw new HttpError(400, 'Spare parts must be issued against a job card');

        const id = (line.partId || line.inventoryItemId || line.toolAssetId)!;
        const info = await itemInfo(tx, a.tenantId, line.category, id);

        if (line.category === 'TOOL_EQUIPMENT') {
          const n = await tx.toolAsset.updateMany({
            where: { id, tenantId: a.tenantId, status: 'AVAILABLE' },
            data: { status: 'CHECKED_OUT', assignedTo: receiver, department: r.department, usedAt: r.jobCardId ? `Job ${r.jobCardId}` : r.department, checkedOutAt: new Date(), expectedReturnAt: line.expectedReturnAt },
          });
          if (n.count !== 1) throw new HttpError(409, `Asset is not available: ${info.name}`);
        } else {
          await moveStock(tx, a.tenantId, line.category, id, -qty);
          if (line.category === 'SPARE_PART') {
            await partMovement(tx, a, id, 'ISSUED', qty, info, r.jobCardId, `Issued to ${receiver} (${r.reference})`);
          }
        }
        await tx.itemRequestLine.update({ where: { id: line.id }, data: { qtyIssued: { increment: qty } } });
        await ledger(tx, a, {
          type: 'ISSUE', ...lineRef(line), itemName: line.description, requestId: r.id, requestLineId: line.id, jobCardId: r.jobCardId, vehicleId: r.vehicleId,
          department: r.department, location: info.location, quantity: -qty, quantityDetail: qty, unitCost: info.cost, recipientName: receiver,
          reason: r.reason, notes: text(req.body.notes), condition: line.category === 'TOOL_EQUIPMENT' ? 'ISSUED' : undefined,
        });
      }

      const fresh = await loadRequest(a.tenantId, r.id, tx);
      const done = fresh.lines.filter((l) => l.qtyApproved > 0).every((l) => l.qtyIssued >= l.qtyApproved);
      await tx.itemRequest.update({ where: { id: r.id }, data: { status: done ? 'ISSUED' : 'PARTIALLY_ISSUED', acknowledgedAt: null, acknowledgedBy: null } });
      return { ...(await loadRequest(a.tenantId, r.id, tx)), awaitingAcknowledgement: true };
    });
  }));

  // Receiver confirms physical receipt.
  router.post('/requests/:id/acknowledge', route(async (a, req) => {
    return txn(async (tx) => {
      await lockRow(tx, 'ItemRequest', String(req.params.id), a.tenantId);
      const r = await loadRequest(a.tenantId, String(req.params.id), tx);
      const isReceiver = r.technicianName === a.name || (a.id && r.technicianId === a.id);
      if (!isReceiver && !ADMINS.includes(a.role)) throw new HttpError(403, 'Only the receiving technician can acknowledge receipt');
      if (!r.lines.some((l) => l.qtyIssued > 0)) throw new HttpError(409, 'Nothing has been issued yet');
      if (r.acknowledgedAt) throw new HttpError(409, 'Already acknowledged');
      await tx.itemRequest.update({ where: { id: r.id }, data: { acknowledgedAt: new Date(), acknowledgedBy: a.name } });
      await ledger(tx, a, { type: 'ACKNOWLEDGE', requestId: r.id, jobCardId: r.jobCardId, department: r.department, recipientName: a.name, quantityDetail: r.lines.reduce((s, l) => s + l.qtyIssued, 0), notes: text(req.body.notes), reason: `Receipt confirmed for ${r.reference}` });
      return loadRequest(a.tenantId, r.id, tx);
    });
  }));

  // =====================================================================
  // 5. RETURNS, DAMAGED, LOST  -> returns wait for inspection
  // =====================================================================
  router.post('/returns', route(async (a, req) => {
    require_(a, 'return:create', 'return items');
    const kind = String(req.body.kind || 'RETURN').toUpperCase();
    if (!['RETURN', 'DAMAGED', 'LOST'].includes(kind)) throw new HttpError(400, 'kind must be RETURN, DAMAGED or LOST');
    const condition = text(req.body.condition);
    if (kind === 'DAMAGED' && !text(req.body.notes)) throw new HttpError(400, 'notes are required for damaged items');

    return txn(async (tx) => {
      let c: InventoryCategory, partId: string | null = null, inventoryItemId: string | null = null, toolAssetId: string | null = null;
      let lineId: string | null = null, jobCardId: string | null = null, vehicleId: string | null = null, department: string | null = null;
      let returnedBy = a.name;
      let qty: number;
      let name: string;

      if (text(req.body.requestLineId)) {
        const line = await tx.itemRequestLine.findFirst({ where: { id: String(req.body.requestLineId), tenantId: a.tenantId } });
        if (!line) throw new HttpError(404, 'Request line not found');
        await lockRow(tx, 'ItemRequestLine', line.id, a.tenantId);
        const fresh = (await tx.itemRequestLine.findUnique({ where: { id: line.id } }))!;
        const r = await loadRequest(a.tenantId, fresh.requestId, tx);
        const owner = r.technicianName === a.name || (a.id && r.technicianId === a.id);
        if (!owner && !can(a, 'return:inspect')) throw new HttpError(403, 'Only the receiving technician or the store can return these items');
        qty = posInt(req.body.quantity ?? 1, 'quantity');
        const outstanding = fresh.qtyIssued - fresh.qtyReturned;
        if (qty > outstanding) throw new HttpError(409, `Only ${outstanding} issued item(s) are still out for "${fresh.description}"`);
        c = fresh.category; partId = fresh.partId; inventoryItemId = fresh.inventoryItemId; toolAssetId = fresh.toolAssetId; lineId = fresh.id;
        jobCardId = r.jobCardId; vehicleId = r.vehicleId; department = r.department; returnedBy = r.technicianName; name = fresh.description;
        await tx.itemRequestLine.update({ where: { id: fresh.id }, data: { qtyReturned: { increment: qty } } });
      } else if (text(req.body.toolAssetId)) {
        const asset = await tx.toolAsset.findFirst({ where: { id: String(req.body.toolAssetId), tenantId: a.tenantId } });
        if (!asset) throw new HttpError(404, 'Asset not found');
        c = 'TOOL_EQUIPMENT'; toolAssetId = asset.id; qty = 1; name = asset.name; returnedBy = asset.assignedTo || a.name; department = asset.department;
      } else {
        throw new HttpError(400, 'requestLineId or toolAssetId is required');
      }

      const id = (partId || inventoryItemId || toolAssetId)!;
      const info = await itemInfo(tx, a.tenantId, c, id);
      const status = kind === 'LOST' ? 'LOST' : 'PENDING_INSPECTION';

      if (c === 'TOOL_EQUIPMENT') {
        const n = await tx.toolAsset.updateMany({
          where: { id, tenantId: a.tenantId, status: 'CHECKED_OUT' },
          data: { status: kind === 'LOST' ? 'LOST' : kind === 'DAMAGED' ? 'DAMAGED' : 'UNDER_REVIEW', ...(condition ? { condition } : {}), ...(kind === 'DAMAGED' ? { condition: 'DAMAGED' } : {}), checkedOutAt: null, expectedReturnAt: null, usedAt: null },
        });
        if (n.count !== 1) throw new HttpError(409, 'Asset is not currently checked out');
      } else if (kind !== 'LOST') {
        await moveStock(tx, a.tenantId, c, id, qty, 'quarantine'); // held aside until inspected
      }

      const ret = await tx.itemReturn.create({
        data: { tenantId: a.tenantId, reference: ref('RET'), requestLineId: lineId, category: c, partId, inventoryItemId, toolAssetId, quantity: qty, kind, condition, returnedBy, receivedBy: a.name, status, notes: text(req.body.notes) },
      });
      await ledger(tx, a, {
        type: kind === 'RETURN' ? 'RETURN' : kind, category: c, partId, inventoryItemId, toolAssetId, itemName: name, requestId: lineId ? (await tx.itemRequestLine.findUnique({ where: { id: lineId } }))!.requestId : undefined,
        requestLineId: lineId, jobCardId, vehicleId, department, location: info.location, quantity: 0, quantityDetail: qty, unitCost: info.cost,
        recipientName: returnedBy, condition, reason: kind === 'RETURN' ? 'Returned for inspection' : `Reported ${kind.toLowerCase()}`, notes: text(req.body.notes),
      });
      return ret;
    });
  }));

  router.get('/returns', route(async (a, req) => {
    require_(a, 'return:inspect', 'view returns');
    const status = text(req.query.status);
    return prisma.itemReturn.findMany({ where: { tenantId: a.tenantId, ...(status ? { status } : {}) }, orderBy: { createdAt: 'desc' }, take: 200 });
  }));

  router.post('/returns/:id/inspect', route(async (a, req) => {
    require_(a, 'return:inspect', 'inspect returns');
    const outcome = String(req.body.outcome || '').toUpperCase();
    if (!['RESTOCK', 'QUARANTINE', 'WRITE_OFF'].includes(outcome)) throw new HttpError(400, 'outcome must be RESTOCK, QUARANTINE or WRITE_OFF');
    if (outcome === 'WRITE_OFF') require_(a, 'stock:writeoff', 'write off returned items');
    const notes = text(req.body.notes);
    if (outcome !== 'RESTOCK' && !notes) throw new HttpError(400, 'notes are required for quarantine / write-off');

    return txn(async (tx) => {
      const existing = await tx.itemReturn.findFirst({ where: { id: String(req.params.id), tenantId: a.tenantId } });
      if (!existing) throw new HttpError(404, 'Return not found');
      if (outcome === 'RESTOCK' && existing.kind === 'DAMAGED') throw new HttpError(400, 'Damaged items cannot go straight back to available stock');
      const newStatus = outcome === 'RESTOCK' ? 'RESTOCKED' : outcome === 'QUARANTINE' ? 'QUARANTINED' : 'WRITTEN_OFF';
      // atomic claim: only one inspector can process a return
      const claimed = await tx.itemReturn.updateMany({
        where: { id: existing.id, tenantId: a.tenantId, status: { in: ['PENDING_INSPECTION', 'QUARANTINED'] } },
        data: { status: newStatus, inspectedBy: a.name, inspectedAt: new Date(), ...(notes ? { notes } : {}) },
      });
      if (claimed.count !== 1) throw new HttpError(409, `Return is already ${existing.status}`);

      const id = (existing.partId || existing.inventoryItemId || existing.toolAssetId)!;
      const info = await itemInfo(tx, a.tenantId, existing.category, id);
      let effect = 0;
      if (existing.category === 'TOOL_EQUIPMENT') {
        const data = outcome === 'RESTOCK'
          ? { status: 'AVAILABLE', assignedTo: null, department: null, location: 'Main Store', ...(text(req.body.condition) ? { condition: String(req.body.condition) } : {}) }
          : outcome === 'QUARANTINE' ? { status: 'UNDER_REVIEW' } : { status: 'WRITTEN_OFF' };
        await tx.toolAsset.update({ where: { id }, data });
        effect = outcome === 'RESTOCK' ? 1 : 0;
      } else {
        // leaves quarantine in every case except staying quarantined
        if (outcome !== 'QUARANTINE' && existing.status !== 'LOST') {
          await moveStock(tx, a.tenantId, existing.category, id, -existing.quantity, 'quarantine');
        }
        if (outcome === 'RESTOCK') {
          await moveStock(tx, a.tenantId, existing.category, id, existing.quantity);
          effect = existing.quantity;
          if (existing.category === 'SPARE_PART') {
            const line = existing.requestLineId ? await tx.itemRequestLine.findUnique({ where: { id: existing.requestLineId }, include: { request: true } }) : null;
            await partMovement(tx, a, id, 'RETURNED', existing.quantity, info, line?.request.jobCardId, `Inspected & restocked (${existing.reference})`);
          }
        }
      }
      const line = existing.requestLineId ? await tx.itemRequestLine.findUnique({ where: { id: existing.requestLineId }, include: { request: true } }) : null;
      await ledger(tx, a, {
        type: outcome === 'WRITE_OFF' ? 'WRITE_OFF' : 'INSPECT', category: existing.category, partId: existing.partId, inventoryItemId: existing.inventoryItemId, toolAssetId: existing.toolAssetId,
        itemName: info.name, requestId: line?.requestId, requestLineId: existing.requestLineId, jobCardId: line?.request.jobCardId, vehicleId: line?.request.vehicleId, department: line?.request.department,
        location: info.location, quantity: effect, quantityDetail: existing.quantity, unitCost: info.cost, recipientName: existing.returnedBy, condition: text(req.body.condition) || existing.condition || undefined,
        reason: `Inspection outcome: ${outcome}`, notes,
      });
      return tx.itemReturn.findUnique({ where: { id: existing.id } });
    });
  }));

  // =====================================================================
  // ADJUSTMENTS, WRITE-OFFS AND STOCKTAKING
  // =====================================================================
  async function applyAdjustment(tx: Tx, a: Actor, c: InventoryCategory, itemId: string, delta: number, reason: string, type: 'ADJUST' | 'WRITE_OFF' | 'STOCKTAKE' = 'ADJUST') {
    if (delta === 0) throw new HttpError(400, 'No change to apply');
    const info = await itemInfo(tx, a.tenantId, c, itemId);
    await moveStock(tx, a.tenantId, c, itemId, delta);
    if (c === 'SPARE_PART') await partMovement(tx, a, itemId, 'ADJUSTED', delta, info, null, `${type}: ${reason}`);
    return ledger(tx, a, { type, category: c, partId: info.partId, inventoryItemId: info.inventoryItemId, itemName: info.name, quantity: delta, quantityDetail: Math.abs(delta), unitCost: info.cost, location: info.location, reason });
  }

  router.post('/adjustments', route(async (a, req) => {
    const c = cat(req.body.category);
    if (c === 'TOOL_EQUIPMENT') throw new HttpError(400, 'Use asset reports for tools');
    const reason = text(req.body.reason);
    if (!reason) throw new HttpError(400, 'reason is required for every adjustment');
    const writeOff = Boolean(req.body.writeOff);
    require_(a, writeOff ? 'stock:writeoff' : 'stock:adjust', writeOff ? 'write off stock' : 'adjust stock');
    const itemId = String(req.body.itemId || '');
    return txn(async (tx) => {
      let delta: number;
      if (req.body.delta !== undefined) delta = Number(req.body.delta);
      else {
        const info = await itemInfo(tx, a.tenantId, c, itemId);
        delta = posInt(req.body.newQuantity, 'newQuantity', 0) - info.available;
      }
      if (!Number.isInteger(delta)) throw new HttpError(400, 'delta must be a whole number');
      if (writeOff && delta >= 0) throw new HttpError(400, 'A write-off must reduce stock');
      return applyAdjustment(tx, a, c, itemId, delta, reason, writeOff ? 'WRITE_OFF' : 'ADJUST');
    });
  }));

  router.post('/stockcounts', route(async (a, req) => {
    require_(a, 'stocktake:count', 'record stock counts');
    const c = cat(req.body.category);
    if (c === 'TOOL_EQUIPMENT') throw new HttpError(400, 'Stock counts apply to parts and consumables');
    const counted = posInt(req.body.countedQty, 'countedQty', 0);
    return txn(async (tx) => {
      const info = await itemInfo(tx, a.tenantId, c, String(req.body.itemId || ''));
      return tx.stockCount.create({
        data: { tenantId: a.tenantId, category: c, partId: info.partId, inventoryItemId: info.inventoryItemId, itemName: info.name, recordedQty: info.available, countedQty: counted, variance: counted - info.available, countedBy: a.name, notes: text(req.body.notes) },
      });
    });
  }));

  router.get('/stockcounts', route(async (a, req) => {
    require_(a, 'report:view', 'view stock counts');
    const status = text(req.query.status);
    return prisma.stockCount.findMany({ where: { tenantId: a.tenantId, ...(status ? { status } : {}) }, orderBy: { createdAt: 'desc' }, take: 200 });
  }));

  router.post('/stockcounts/:id/approve', route(async (a, req) => {
    require_(a, 'stocktake:approve', 'approve stock count variances');
    const approve = req.body.approve !== false;
    return txn(async (tx) => {
      const sc = await tx.stockCount.findFirst({ where: { id: String(req.params.id), tenantId: a.tenantId } });
      if (!sc) throw new HttpError(404, 'Stock count not found');
      if (sc.countedBy === a.name && !ADMINS.includes(a.role)) throw new HttpError(403, 'A different person must approve the stock count');
      const claimed = await tx.stockCount.updateMany({ where: { id: sc.id, status: 'PENDING' }, data: { status: approve ? 'APPROVED' : 'REJECTED', approvedBy: a.name, approvedAt: new Date() } });
      if (claimed.count !== 1) throw new HttpError(409, `Stock count is already ${sc.status}`);
      if (approve && sc.variance !== 0) {
        await applyAdjustment(tx, a, sc.category, (sc.partId || sc.inventoryItemId)!, sc.variance, `Stocktake variance (counted ${sc.countedQty}, recorded ${sc.recordedQty})`, 'STOCKTAKE');
      }
      return tx.stockCount.findUnique({ where: { id: sc.id } });
    });
  }));

  // =====================================================================
  // 4 & 6. TRANSACTIONS, REPORTS, EXPORT
  // =====================================================================
  function txWhere(a: Actor, q: any): Prisma.InventoryTransactionWhereInput {
    const w: Prisma.InventoryTransactionWhereInput = { tenantId: a.tenantId };
    if (q.category) w.category = cat(q.category);
    if (text(q.type)) w.type = String(q.type).toUpperCase();
    if (text(q.department)) w.department = String(q.department);
    if (text(q.jobCardId)) w.jobCardId = String(q.jobCardId);
    if (text(q.location)) w.location = String(q.location);
    if (text(q.requestId)) w.requestId = String(q.requestId);
    if (text(q.itemId)) w.OR = [{ partId: String(q.itemId) }, { inventoryItemId: String(q.itemId) }, { toolAssetId: String(q.itemId) }];
    if (text(q.employee) || text(q.technician)) {
      const e = String(q.employee || q.technician);
      w.AND = [{ OR: [{ recipientName: e }, { actorName: e }] }];
    }
    if (text(q.from) || text(q.to)) {
      w.createdAt = {};
      if (text(q.from)) w.createdAt.gte = new Date(String(q.from));
      if (text(q.to)) { const t = new Date(String(q.to)); if (String(q.to).length <= 10) t.setUTCHours(23, 59, 59, 999); w.createdAt.lte = t; }
    }
    return w;
  }

  router.get('/transactions', route(async (a, req) => {
    require_(a, 'report:view', 'view the movement history');
    const limit = Math.min(Number(req.query.limit) || 200, 1000);
    const rows = await prisma.inventoryTransaction.findMany({ where: txWhere(a, req.query), orderBy: { createdAt: 'desc' }, take: limit });
    return can(a, 'report:cost') ? rows : rows.map((r) => ({ ...r, unitCost: 0 }));
  }));

  // Movement trail of a single item: where it came from, who handled it, where it went.
  router.get('/items/:category/:id/history', route(async (a, req) => {
    require_(a, 'report:view', 'view item history');
    const c = cat(String(req.params.category).toUpperCase());
    const id = String(req.params.id);
    const where: Prisma.InventoryTransactionWhereInput = { tenantId: a.tenantId, ...(c === 'SPARE_PART' ? { partId: id } : c === 'CONSUMABLE' ? { inventoryItemId: id } : { toolAssetId: id }) };
    const info = await itemInfo(prisma as any, a.tenantId, c, id);
    const history = await prisma.inventoryTransaction.findMany({ where, orderBy: { createdAt: 'asc' } });
    let currentStatus: any = { available: info.available, location: info.location };
    if (c === 'TOOL_EQUIPMENT') currentStatus = await prisma.toolAsset.findFirst({ where: { id, tenantId: a.tenantId } });
    return { item: info.name, current: currentStatus, history };
  }));

  async function buildReports(a: Actor, q: any) {
    const showCost = can(a, 'report:cost');
    const now = new Date();
    const [parts, items, assets, tx, counts, returns] = await Promise.all([
      prisma.partCatalog.findMany({ where: { tenantId: a.tenantId, ...(text(q.location) ? { location: String(q.location) } : {}) } }),
      prisma.inventoryItem.findMany({ where: { tenantId: a.tenantId, ...(text(q.location) ? { location: String(q.location) } : {}) } }),
      prisma.toolAsset.findMany({ where: { tenantId: a.tenantId, ...(text(q.location) ? { location: String(q.location) } : {}) } }),
      prisma.inventoryTransaction.findMany({ where: txWhere(a, q), orderBy: { createdAt: 'desc' }, take: 5000 }),
      prisma.stockCount.findMany({ where: { tenantId: a.tenantId, variance: { not: 0 } }, orderBy: { createdAt: 'desc' }, take: 200 }),
      prisma.itemReturn.findMany({ where: { tenantId: a.tenantId }, orderBy: { createdAt: 'desc' }, take: 500 }),
    ]);

    const wantCat = q.category ? cat(q.category) : undefined;
    const balances = [
      ...(!wantCat || wantCat === 'SPARE_PART' ? parts.map((p) => ({ category: 'SPARE_PART', id: p.id, code: p.partNumber, name: p.description, location: p.location, onHand: p.stockQuantity, quarantined: p.quarantineQuantity, reorderLevel: p.reorderLevel, unitCost: showCost ? p.costPrice : undefined, value: showCost ? p.costPrice * p.stockQuantity : undefined })) : []),
      ...(!wantCat || wantCat === 'CONSUMABLE' ? items.map((i) => ({ category: 'CONSUMABLE', id: i.id, code: i.sku, name: i.name, location: i.location, onHand: i.quantityOnHand, quarantined: i.quarantineQuantity, reorderLevel: i.reorderLevel, unitCost: showCost ? i.unitCost : undefined, value: showCost ? i.unitCost * i.quantityOnHand : undefined })) : []),
      ...(!wantCat || wantCat === 'TOOL_EQUIPMENT' ? assets.filter((t) => !['LOST', 'WRITTEN_OFF'].includes(t.status)).map((t) => ({ category: 'TOOL_EQUIPMENT', id: t.id, code: t.assetNumber, name: t.name, location: t.location, onHand: t.status === 'AVAILABLE' || t.status === 'FIXED' ? 1 : 0, quarantined: t.status === 'UNDER_REVIEW' || t.status === 'DAMAGED' ? 1 : 0, reorderLevel: 0, status: t.status, unitCost: showCost ? t.cost : undefined, value: showCost ? t.cost : undefined })) : []),
    ];

    const lowStock = balances
      .filter((b) => b.category !== 'TOOL_EQUIPMENT' && b.onHand <= b.reorderLevel)
      .map((b) => ({ ...b, recommendedReorder: Math.max(b.reorderLevel * 2 - b.onHand, 1) }));

    const byType: Record<string, number> = {};
    for (const t of tx) byType[t.type] = (byType[t.type] || 0) + (t.quantityDetail || 0);

    // parts issued per job card (net of inspected restocks)
    const jobMap = new Map<string, any>();
    for (const t of tx.filter((x) => x.category === 'SPARE_PART' && x.jobCardId && (x.type === 'ISSUE' || (x.type === 'INSPECT' && x.quantity > 0)))) {
      const key = `${t.jobCardId}|${t.partId}`;
      const row = jobMap.get(key) || { jobCardId: t.jobCardId, vehicleId: t.vehicleId, partId: t.partId, item: t.itemName, netQty: 0, cost: 0 };
      const signed = t.type === 'ISSUE' ? t.quantityDetail : -t.quantityDetail;
      row.netQty += signed; row.cost += signed * t.unitCost;
      jobMap.set(key, row);
    }
    const partsByJob = [...jobMap.values()].map((r) => ({ ...r, cost: showCost ? r.cost : undefined }));

    const deptMap = new Map<string, any>();
    for (const t of tx.filter((x) => x.category === 'CONSUMABLE' && x.type === 'ISSUE')) {
      const isIndiv = t.department === 'Individual Issue' || t.department === 'Individual' || !t.department;
      const targetLabel = isIndiv ? `Individual: ${t.recipientName || 'Technician'}` : (t.department || 'Workshop');
      const key = `${targetLabel}|${t.inventoryItemId}`;
      const row = deptMap.get(key) || { department: targetLabel, recipientName: t.recipientName || 'Technician', item: t.itemName, quantity: 0, cost: 0 };
      row.quantity += t.quantityDetail; row.cost += t.quantityDetail * t.unitCost;
      deptMap.set(key, row);
    }
    const consumablesByDepartment = [...deptMap.values()].map((r) => ({ ...r, cost: showCost ? r.cost : undefined }));

    const toolsAssigned = assets.filter((t) => ['CHECKED_OUT', 'FIXED'].includes(t.status)).map((t) => ({ id: t.id, assetNumber: t.assetNumber, name: t.name, status: t.status, assignedTo: t.assignedTo, department: t.department, location: t.location, usedAt: t.usedAt, checkedOutAt: t.checkedOutAt, expectedReturnAt: t.expectedReturnAt }));
    const overdueTools = toolsAssigned.filter((t) => t.status === 'CHECKED_OUT' && t.expectedReturnAt && t.expectedReturnAt < now);
    const lostDamagedAssets = assets.filter((t) => ['LOST', 'DAMAGED', 'WRITTEN_OFF'].includes(t.status)).map((t) => ({ id: t.id, assetNumber: t.assetNumber, name: t.name, status: t.status, cost: showCost ? t.cost : undefined }));
    const lostDamagedReturns = returns.filter((r) => ['LOST', 'WRITTEN_OFF'].includes(r.status) || r.kind === 'DAMAGED');

    const valuation = showCost
      ? {
          spareParts: parts.reduce((s, p) => s + p.costPrice * p.stockQuantity, 0),
          sparePartsAtRetail: parts.reduce((s, p) => s + p.unitPrice * p.stockQuantity, 0),
          consumables: items.reduce((s, i) => s + i.unitCost * i.quantityOnHand, 0),
          assets: assets.filter((t) => !['LOST', 'WRITTEN_OFF'].includes(t.status)).reduce((s, t) => s + t.cost, 0),
          total: 0,
        }
      : undefined;
    if (valuation) valuation.total = valuation.spareParts + valuation.consumables + valuation.assets;

    return {
      balances, lowStock, valuation, movementTotalsByType: byType, partsByJob, consumablesByDepartment,
      toolsAssigned, overdueTools, lostDamagedAssets, lostDamagedReturns,
      pendingInspections: returns.filter((r) => r.status === 'PENDING_INSPECTION').length,
      stockVariances: counts,
      transactionCount: tx.length,
    };
  }

  router.get('/reports/summary', route(async (a, req) => {
    require_(a, 'report:view', 'view inventory reports');
    return buildReports(a, req.query);
  }));

  function toCsv(rows: any[]): string {
    if (!rows.length) return '';
    const cols = [...new Set(rows.flatMap((r) => Object.keys(r)))];
    const esc = (v: any) => {
      if (v === null || v === undefined) return '';
      let s = v instanceof Date ? v.toISOString() : typeof v === 'object' ? JSON.stringify(v) : String(v);
      if (/^[=+\-@]/.test(s)) s = `'${s}`; // neutralise spreadsheet formulas
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    return [cols.join(','), ...rows.map((r) => cols.map((c) => esc(r[c])).join(','))].join('\n');
  }

  router.get('/reports/export', route(async (a, req, res) => {
    require_(a, 'report:view', 'export inventory reports');
    const type = String(req.query.report || 'transactions');
    let rows: any[];
    if (type === 'transactions') {
      rows = await prisma.inventoryTransaction.findMany({ where: txWhere(a, req.query), orderBy: { createdAt: 'desc' }, take: 20000 });
      if (!can(a, 'report:cost')) rows = rows.map((r) => ({ ...r, unitCost: 0 }));
    } else {
      const r: any = await buildReports(a, req.query);
      const map: Record<string, string> = { balances: 'balances', lowStock: 'lowStock', partsByJob: 'partsByJob', consumables: 'consumablesByDepartment', toolsAssigned: 'toolsAssigned', overdueTools: 'overdueTools', lostDamaged: 'lostDamagedAssets', variances: 'stockVariances' };
      if (!map[type]) throw new HttpError(400, `Unknown report. Use transactions, ${Object.keys(map).join(', ')}`);
      rows = r[map[type]];
    }
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="inventory-${type}.csv"`);
    res.send(toCsv(rows));
  }));

  // Job costing: parts issued to a job (net of restocked returns) for estimates / invoices.
  router.get('/jobs/:jobId/costing', route(async (a, req) => {
    require_(a, 'job:costing', 'view job costing');
    const job = await prisma.jobCard.findFirst({ where: { id: String(req.params.jobId), tenantId: a.tenantId } });
    if (!job) throw new HttpError(404, 'Job card not found');
    const rows = await prisma.inventoryTransaction.findMany({
      where: { tenantId: a.tenantId, jobCardId: job.id, category: 'SPARE_PART', OR: [{ type: 'ISSUE' }, { type: 'INSPECT', quantity: { gt: 0 } }] },
    });
    const map = new Map<string, { partId: string; description: string; qty: number }>();
    for (const t of rows) {
      const k = t.partId!;
      const e = map.get(k) || { partId: k, description: t.itemName || '', qty: 0 };
      e.qty += t.type === 'ISSUE' ? t.quantityDetail : -t.quantityDetail;
      map.set(k, e);
    }
    const partIds = [...map.keys()];
    const catalog = await prisma.partCatalog.findMany({ where: { id: { in: partIds }, tenantId: a.tenantId } });
    const lines = [...map.values()].filter((l) => l.qty > 0).map((l) => {
      const p = catalog.find((c) => c.id === l.partId);
      return { ...l, unitCost: p?.costPrice ?? 0, unitPrice: p?.unitPrice ?? 0, totalCost: (p?.costPrice ?? 0) * l.qty, totalPrice: (p?.unitPrice ?? 0) * l.qty };
    });
    const totals = { cost: lines.reduce((s, l) => s + l.totalCost, 0), price: lines.reduce((s, l) => s + l.totalPrice, 0) };
    return can(a, 'report:cost') ? { jobCardId: job.id, jobNumber: job.jobNumber, vehicleId: job.vehicleId, lines, totals } : { jobCardId: job.id, jobNumber: job.jobNumber, vehicleId: job.vehicleId, lines: lines.map((l) => ({ ...l, unitCost: undefined, totalCost: undefined })), totals: { price: totals.price } };
  }));

  // =====================================================================
  // STOREKEEPER NOTIFICATIONS
  // =====================================================================
  router.get('/notifications', route(async (a, req) => {
    require_(a, 'notification:view', 'view store notifications');
    return prisma.storeNotification.findMany({
      where: { tenantId: a.tenantId, targetRole: 'STOREKEEPER', ...(req.query.unread === '1' ? { readAt: null } : {}) },
      orderBy: { createdAt: 'desc' }, take: 100,
    });
  }));

  router.post('/notifications/read', route(async (a, req) => {
    require_(a, 'notification:view', 'update store notifications');
    const ids: string[] | undefined = Array.isArray(req.body.ids) ? req.body.ids : undefined;
    const r = await prisma.storeNotification.updateMany({
      where: { tenantId: a.tenantId, readAt: null, ...(ids ? { id: { in: ids } } : {}) },
      data: { readAt: new Date() },
    });
    return { updated: r.count };
  }));

  // What the current role can do (lets clients hide controls).
  router.get('/me', route(async (a) => ({
    name: a.name, role: a.role, tenantId: a.tenantId,
    permissions: Object.keys(INVENTORY_PERMS).filter((p) => can(a, p)),
  })));

  return router;
}
