-- CreateEnum
CREATE TYPE "InventoryCategory" AS ENUM ('SPARE_PART', 'TOOL_EQUIPMENT', 'CONSUMABLE');

-- AlterEnum
ALTER TYPE "Role" ADD VALUE 'INVENTORY_MANAGER';

-- AlterTable
ALTER TABLE "PartCatalog" ADD COLUMN     "location" TEXT NOT NULL DEFAULT 'Main Store',
ADD COLUMN     "quarantineQuantity" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "StockMovement" ADD COLUMN     "reference" TEXT,
ADD COLUMN     "supplierName" TEXT,
ADD COLUMN     "tenantId" TEXT,
ADD COLUMN     "unitCost" DOUBLE PRECISION,
ADD COLUMN     "unitPrice" DOUBLE PRECISION;

-- CreateTable
CREATE TABLE "InventoryItem" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "unit" TEXT NOT NULL DEFAULT 'pcs',
    "description" TEXT,
    "quantityOnHand" INTEGER NOT NULL DEFAULT 0,
    "quarantineQuantity" INTEGER NOT NULL DEFAULT 0,
    "reorderLevel" INTEGER NOT NULL DEFAULT 5,
    "unitCost" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "location" TEXT NOT NULL DEFAULT 'Main Store',
    "supplierName" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ToolAsset" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "assetNumber" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "serialNumber" TEXT,
    "purchaseDate" TIMESTAMP(3),
    "cost" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "condition" TEXT NOT NULL DEFAULT 'GOOD',
    "status" TEXT NOT NULL DEFAULT 'AVAILABLE',
    "isFixed" BOOLEAN NOT NULL DEFAULT false,
    "location" TEXT NOT NULL DEFAULT 'Main Store',
    "assignedTo" TEXT,
    "department" TEXT,
    "usedAt" TEXT,
    "checkedOutAt" TIMESTAMP(3),
    "expectedReturnAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ToolAsset_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ItemRequest" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "reference" TEXT NOT NULL,
    "technicianId" TEXT,
    "technicianName" TEXT NOT NULL,
    "jobCardId" TEXT,
    "vehicleId" TEXT,
    "department" TEXT,
    "reason" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "decidedBy" TEXT,
    "decidedAt" TIMESTAMP(3),
    "decisionNotes" TEXT,
    "acknowledgedBy" TEXT,
    "acknowledgedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ItemRequest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ItemRequestLine" (
    "id" TEXT NOT NULL,
    "requestId" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "category" "InventoryCategory" NOT NULL,
    "partId" TEXT,
    "inventoryItemId" TEXT,
    "toolAssetId" TEXT,
    "description" TEXT NOT NULL,
    "qtyRequested" INTEGER NOT NULL,
    "qtyApproved" INTEGER NOT NULL DEFAULT 0,
    "qtyIssued" INTEGER NOT NULL DEFAULT 0,
    "qtyReturned" INTEGER NOT NULL DEFAULT 0,
    "expectedReturnAt" TIMESTAMP(3),

    CONSTRAINT "ItemRequestLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ItemReturn" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "reference" TEXT NOT NULL,
    "requestLineId" TEXT,
    "category" "InventoryCategory" NOT NULL,
    "partId" TEXT,
    "inventoryItemId" TEXT,
    "toolAssetId" TEXT,
    "quantity" INTEGER NOT NULL,
    "kind" TEXT NOT NULL DEFAULT 'RETURN',
    "condition" TEXT,
    "returnedBy" TEXT NOT NULL,
    "receivedBy" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING_INSPECTION',
    "inspectedBy" TEXT,
    "inspectedAt" TIMESTAMP(3),
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ItemReturn_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InventoryTransaction" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "reference" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "category" "InventoryCategory",
    "partId" TEXT,
    "inventoryItemId" TEXT,
    "toolAssetId" TEXT,
    "itemName" TEXT,
    "requestId" TEXT,
    "requestLineId" TEXT,
    "jobCardId" TEXT,
    "vehicleId" TEXT,
    "department" TEXT,
    "location" TEXT,
    "quantity" INTEGER NOT NULL DEFAULT 0,
    "quantityDetail" INTEGER NOT NULL DEFAULT 0,
    "unitCost" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "actorId" TEXT,
    "actorName" TEXT NOT NULL,
    "actorRole" TEXT NOT NULL,
    "recipientName" TEXT,
    "condition" TEXT,
    "reason" TEXT,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InventoryTransaction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "StockCount" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "category" "InventoryCategory" NOT NULL,
    "partId" TEXT,
    "inventoryItemId" TEXT,
    "itemName" TEXT NOT NULL,
    "recordedQty" INTEGER NOT NULL,
    "countedQty" INTEGER NOT NULL,
    "variance" INTEGER NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "countedBy" TEXT NOT NULL,
    "approvedBy" TEXT,
    "approvedAt" TIMESTAMP(3),
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StockCount_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "StoreNotification" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "targetRole" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "requestId" TEXT,
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StoreNotification_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "InventoryItem_tenantId_idx" ON "InventoryItem"("tenantId");

-- CreateIndex
CREATE UNIQUE INDEX "InventoryItem_tenantId_sku_key" ON "InventoryItem"("tenantId", "sku");

-- CreateIndex
CREATE INDEX "ToolAsset_tenantId_status_idx" ON "ToolAsset"("tenantId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "ToolAsset_tenantId_assetNumber_key" ON "ToolAsset"("tenantId", "assetNumber");

-- CreateIndex
CREATE INDEX "ItemRequest_tenantId_status_idx" ON "ItemRequest"("tenantId", "status");

-- CreateIndex
CREATE INDEX "ItemRequest_tenantId_technicianName_idx" ON "ItemRequest"("tenantId", "technicianName");

-- CreateIndex
CREATE UNIQUE INDEX "ItemRequest_tenantId_reference_key" ON "ItemRequest"("tenantId", "reference");

-- CreateIndex
CREATE INDEX "ItemRequestLine_requestId_idx" ON "ItemRequestLine"("requestId");

-- CreateIndex
CREATE INDEX "ItemRequestLine_tenantId_idx" ON "ItemRequestLine"("tenantId");

-- CreateIndex
CREATE INDEX "ItemReturn_tenantId_status_idx" ON "ItemReturn"("tenantId", "status");

-- CreateIndex
CREATE INDEX "InventoryTransaction_tenantId_createdAt_idx" ON "InventoryTransaction"("tenantId", "createdAt");

-- CreateIndex
CREATE INDEX "InventoryTransaction_tenantId_partId_idx" ON "InventoryTransaction"("tenantId", "partId");

-- CreateIndex
CREATE INDEX "InventoryTransaction_tenantId_inventoryItemId_idx" ON "InventoryTransaction"("tenantId", "inventoryItemId");

-- CreateIndex
CREATE INDEX "InventoryTransaction_tenantId_toolAssetId_idx" ON "InventoryTransaction"("tenantId", "toolAssetId");

-- CreateIndex
CREATE INDEX "InventoryTransaction_tenantId_jobCardId_idx" ON "InventoryTransaction"("tenantId", "jobCardId");

-- CreateIndex
CREATE INDEX "InventoryTransaction_tenantId_requestId_idx" ON "InventoryTransaction"("tenantId", "requestId");

-- CreateIndex
CREATE INDEX "StockCount_tenantId_status_idx" ON "StockCount"("tenantId", "status");

-- CreateIndex
CREATE INDEX "StoreNotification_tenantId_targetRole_readAt_idx" ON "StoreNotification"("tenantId", "targetRole", "readAt");

-- AddForeignKey
ALTER TABLE "ItemRequestLine" ADD CONSTRAINT "ItemRequestLine_requestId_fkey" FOREIGN KEY ("requestId") REFERENCES "ItemRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Immutable audit ledger: block UPDATE and DELETE on InventoryTransaction.
CREATE OR REPLACE FUNCTION inventory_transaction_immutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'InventoryTransaction is append-only; record a correcting transaction instead';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS inventory_transaction_no_update ON "InventoryTransaction";
CREATE TRIGGER inventory_transaction_no_update
BEFORE UPDATE OR DELETE ON "InventoryTransaction"
FOR EACH ROW EXECUTE FUNCTION inventory_transaction_immutable();

-- Stock can never go negative.
ALTER TABLE "PartCatalog" ADD CONSTRAINT "PartCatalog_stock_nonneg" CHECK ("stockQuantity" >= 0 AND "quarantineQuantity" >= 0);
ALTER TABLE "InventoryItem" ADD CONSTRAINT "InventoryItem_stock_nonneg" CHECK ("quantityOnHand" >= 0 AND "quarantineQuantity" >= 0);
