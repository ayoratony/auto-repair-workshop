import path from 'path';
import express, { Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { PrismaClient, JobStatus, EstimateStatus, PaymentStatus, Role, ClientCategory } from '@prisma/client';
import {
  ASSETS_BUCKET,
  uploadWorkshopAsset,
  downloadWorkshopAsset,
  getWorkshopAssetPresignedUrl,
  workshopAssetExists,
  deleteWorkshopAsset,
} from './storage';
import { createInventoryRouter } from './inventory';
import {
  hashPassword,
  comparePassword,
  generateToken,
  seedInitialOwner,
  createAuthMiddleware,
  requireRoles,
} from './auth';

dotenv.config({ path: path.resolve(__dirname, '../../.env.local') });
dotenv.config();

const app = express();
const prisma = new PrismaClient();
const PORT = Number(process.env.PORT) || 5001;

app.use(cors());
app.use(express.json({ limit: '15mb' }));
app.use(createAuthMiddleware(prisma));

// Helper to get or create the active workshop tenant
async function getActiveTenant() {
  let tenant = await prisma.tenant.findFirst();
  if (!tenant) {
    tenant = await prisma.tenant.create({
      data: {
        name: 'AutoKe Auto Workshop',
        address: 'Industrial Area, Nairobi',
        taxPin: 'P051234567X',
      },
    });
  } else if (tenant.name === 'MechanicHQ Auto Workshop') {
    tenant = await prisma.tenant.update({
      where: { id: tenant.id },
      data: { name: 'AutoKe Auto Workshop' },
    });
  }
  return tenant;
}

// Helper to generate sequential, collision-free Job Number (e.g. JC01001)
async function generateJobNumber(): Promise<string> {
  const existingJobs = await prisma.jobCard.findMany({
    select: { jobNumber: true },
  });
  let maxNum = 1000;
  for (const j of existingJobs) {
    if (j.jobNumber) {
      const m = j.jobNumber.match(/(\d+)$/);
      if (m) {
        const parsed = parseInt(m[1], 10);
        if (parsed > maxNum) maxNum = parsed;
      }
    }
  }
  return `JC0${maxNum + 1}`;
}

// Helper to sanitize & parse client/vehicle category
function parseCategory(val: any): ClientCategory {
  if (!val) return ClientCategory.PERSONAL;
  const upper = String(val).trim().toUpperCase();
  if (upper === 'GOVERNMENT') return ClientCategory.GOVERNMENT;
  if (upper === 'SCHOOL') return ClientCategory.SCHOOL;
  if (upper === 'ORGANIZATION') return ClientCategory.ORGANIZATION;
  return ClientCategory.PERSONAL;
}

// Workshop inventory: requests, issuance, assets, consumables, audit ledger
app.use('/api/inventory', createInventoryRouter(prisma, async () => (await getActiveTenant()).id));

// In-flight deduplication map to prevent duplicate job creation on rapid/double clicks
const inFlightJobCreations = new Map<string, Promise<any>>();

// Health check endpoint
app.get('/api/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok', message: 'Auto Repair API is running' });
});

// ==========================================
// DASHBOARD SUMMARY & ANALYTICS API
// ==========================================
app.get('/api/dashboard', async (_req: Request, res: Response) => {
  try {
    const [
      jobs,
      estimates,
      invoices,
      parts,
      customersCount,
      employeesCount,
      appointments,
      expenses,
    ] = await Promise.all([
      prisma.jobCard.findMany({
        include: { customer: true, vehicle: true },
        orderBy: { updatedAt: 'desc' },
      }),
      prisma.estimate.findMany({
        include: {
          lineItems: true,
          jobCard: { include: { customer: true, vehicle: true } },
          invoice: true,
        },
        orderBy: { updatedAt: 'desc' },
      }),
      prisma.invoice.findMany({
        include: {
          estimate: {
            include: {
              lineItems: true,
              jobCard: { include: { customer: true, vehicle: true } },
            },
          },
        },
        orderBy: { updatedAt: 'desc' },
      }),
      prisma.partCatalog.findMany(),
      prisma.customer.count(),
      prisma.user.count(),
      prisma.appointment.findMany({
        orderBy: { scheduledAt: 'asc' },
      }),
      prisma.expense.findMany({
        orderBy: { incurredAt: 'desc' },
      }),
    ]);

    // Calculate Total Collected Revenue and Outstanding Debtors Balance
    let totalRevenue = 0;
    let outstandingBalance = 0;

    for (const inv of invoices) {
      const estTotal = inv.estimate?.total || 0;
      if (inv.paymentStatus === 'PAID') {
        totalRevenue += inv.amountPaid > 0 ? inv.amountPaid : estTotal;
      } else if (inv.paymentStatus === 'PARTIAL') {
        totalRevenue += inv.amountPaid;
        outstandingBalance += inv.balanceDue > 0 ? inv.balanceDue : Math.max(0, estTotal - inv.amountPaid);
      } else if (inv.paymentStatus === 'UNPAID') {
        outstandingBalance += inv.balanceDue > 0 ? inv.balanceDue : estTotal;
      }
    }

    if (totalRevenue === 0) {
      for (const est of estimates) {
        if (est.status === 'APPROVED') {
          totalRevenue += est.total;
        }
      }
    }

    // Calculate Labour vs Parts Revenue and Parts COGS
    let labourRevenue = 0;
    let partsRevenue = 0;
    let partsCostTotal = 0;
    const partMap = new Map(parts.map((p) => [p.id, p]));

    for (const est of estimates) {
      if (est.status === 'APPROVED' || est.invoice) {
        for (const li of est.lineItems || []) {
          if ((li.itemType || 'PART').toUpperCase() === 'LABOUR') {
            labourRevenue += li.total;
          } else {
            partsRevenue += li.total;
            const matchedPart =
              (li.partId && partMap.get(li.partId)) ||
              parts.find(
                (p) =>
                  li.description.toLowerCase().includes(p.partNumber.toLowerCase()) ||
                  li.description.toLowerCase().includes(p.description.toLowerCase())
              );
            const unitCost =
              matchedPart && matchedPart.costPrice > 0
                ? matchedPart.costPrice
                : li.unitPrice * 0.65;
            partsCostTotal += unitCost * li.quantity;
          }
        }
      }
    }

    const expensesTotal = expenses.reduce((sum, e) => sum + e.amount, 0);
    const netProfit = totalRevenue - partsCostTotal - expensesTotal;

    const stockValuationCost = parts.reduce(
      (sum, p) => sum + p.stockQuantity * (p.costPrice > 0 ? p.costPrice : p.unitPrice * 0.65),
      0
    );
    const stockValuationRetail = parts.reduce(
      (sum, p) => sum + p.stockQuantity * p.unitPrice,
      0
    );

    const now = new Date();
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const startOfWeek = new Date(now.getTime() - 7 * 86400000);
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

    const activeJobsCount = jobs.filter((j) => j.status !== 'COMPLETED').length;
    const completedJobsCount = jobs.filter((j) => j.status === 'COMPLETED').length;
    const todayJobsCount = jobs.filter((j) => new Date(j.createdAt) >= startOfToday).length;
    const weekJobsCount = jobs.filter((j) => new Date(j.createdAt) >= startOfWeek).length;
    const monthJobsCount = jobs.filter((j) => new Date(j.createdAt) >= startOfMonth).length;
    const overdueJobsCount = jobs.filter(
      (j) => j.status !== 'COMPLETED' && j.dueDate && new Date(j.dueDate) < now
    ).length;

    const pendingEstimatesCount = estimates.filter(
      (e) => e.status === 'DRAFT' || e.status === 'SENT'
    ).length;
    const lowStockCount = parts.filter(
      (p) => p.stockQuantity <= (p.reorderLevel || 5)
    ).length;

    // Mechanic Productivity & Commission breakdown
    const techStatsMap = new Map<
      string,
      {
        technician: string;
        totalJobs: number;
        completedJobs: number;
        activeJobs: number;
        estimatedHours: number;
        actualHours: number;
        labourGenerated: number;
        commissionEarned: number;
      }
    >();

    for (const j of jobs) {
      const techName = j.technician || 'Unassigned';
      const entry = techStatsMap.get(techName) || {
        technician: techName,
        totalJobs: 0,
        completedJobs: 0,
        activeJobs: 0,
        estimatedHours: 0,
        actualHours: 0,
        labourGenerated: 0,
        commissionEarned: 0,
      };
      entry.totalJobs += 1;
      if (j.status === 'COMPLETED' || j.status === 'READY') {
        entry.completedJobs += 1;
      } else {
        entry.activeJobs += 1;
      }
      const estH = j.estimatedHours || 2;
      const actH = j.actualHours || (j.status === 'COMPLETED' ? estH : 0);
      entry.estimatedHours += estH;
      entry.actualHours += actH;
      const jobLabour = estH * 1500;
      entry.labourGenerated += jobLabour;
      entry.commissionEarned += Math.round(jobLabour * 0.15);
      techStatsMap.set(techName, entry);
    }

    // Top Serviced Vehicles (by make/model & registration)
    const vehicleCountsMap = new Map<
      string,
      { registrationNo: string; makeModel: string; customerName: string; jobsCount: number; lastService: string }
    >();
    for (const j of jobs) {
      const reg = j.vehicle?.registrationNo || 'UNKNOWN';
      const existingV = vehicleCountsMap.get(reg) || {
        registrationNo: reg,
        makeModel: `${j.vehicle?.make || ''} ${j.vehicle?.model || ''}`.trim() || 'Vehicle',
        customerName: j.customer?.name || 'Customer',
        jobsCount: 0,
        lastService: j.workRequested || 'General Service',
      };
      existingV.jobsCount += 1;
      vehicleCountsMap.set(reg, existingV);
    }
    const topVehicles = Array.from(vehicleCountsMap.values())
      .sort((a, b) => b.jobsCount - a.jobsCount)
      .slice(0, 6);

    // Most Used Spare Parts across Estimates/Invoices
    const partUsageMap = new Map<
      string,
      { description: string; quantityUsed: number; revenueGenerated: number }
    >();
    for (const est of estimates) {
      for (const li of est.lineItems || []) {
        if ((li.itemType || 'PART').toUpperCase() === 'LABOUR') continue;
        const key = li.description.trim();
        const curr = partUsageMap.get(key) || {
          description: key,
          quantityUsed: 0,
          revenueGenerated: 0,
        };
        curr.quantityUsed += li.quantity;
        curr.revenueGenerated += li.total;
        partUsageMap.set(key, curr);
      }
    }
    const topParts = Array.from(partUsageMap.values())
      .sort((a, b) => b.quantityUsed - a.quantityUsed)
      .slice(0, 6);

    // Service Due Reminders (from JobCards/Vehicles with odometer or nextServiceMileage)
    const serviceReminders = jobs.slice(0, 8).map((j) => {
      const currentOdo = j.odometer || 0;
      const nextOdo = j.nextServiceMileage || j.vehicle?.nextServiceMileage || (currentOdo > 0 ? currentOdo + 5000 : 5000);
      return {
        jobId: j.id,
        jobNumber: j.jobNumber || j.id.substring(0, 6).toUpperCase(),
        customerName: j.customer?.name || 'Customer',
        phone: j.customer?.phone || '',
        registrationNo: j.vehicle?.registrationNo || '-',
        makeModel: `${j.vehicle?.make || ''} ${j.vehicle?.model || ''}`.trim(),
        currentOdometer: currentOdo,
        nextServiceMileage: nextOdo,
        nextServiceDate:
          j.nextServiceDate ||
          j.vehicle?.nextServiceDate ||
          new Date(new Date(j.createdAt).getTime() + 90 * 86400000).toISOString(),
        status: j.status,
      };
    });

    // Weekly Jobs (Mon - Sat counts based on createdAt day of week)
    const weeklyCounts = [0, 0, 0, 0, 0, 0]; // Mon(0) .. Sat(5)
    for (const job of jobs) {
      const day = new Date(job.createdAt).getDay(); // 0=Sun, 1=Mon, ..., 6=Sat
      if (day >= 1 && day <= 6) {
        weeklyCounts[day - 1] += 1;
      } else if (day === 0) {
        weeklyCounts[5] += 1;
      }
    }

    // Build Recent Activities from real database events
    const activities: Array<{
      title: string;
      subtitle: string;
      timestamp: Date;
      type: string;
    }> = [];

    for (const job of jobs.slice(0, 5)) {
      activities.push({
        title: `${job.customer.name} (${job.jobNumber || job.id.substring(0, 6).toUpperCase()})`,
        subtitle: `${job.vehicle.make || ''} ${job.vehicle.model || ''} - ${job.workRequested || 'Service'} [${job.status}]`,
        timestamp: job.updatedAt,
        type: job.status === 'COMPLETED' ? 'completed' : 'job',
      });
    }

    for (const est of estimates.slice(0, 3)) {
      activities.push({
        title: `Estimate for ${est.jobCard?.customer?.name || 'Customer'}`,
        subtitle: `Total: KSH ${est.total.toFixed(2)} (${est.status})`,
        timestamp: est.updatedAt,
        type: 'estimate',
      });
    }

    activities.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());

    res.json({
      totalRevenue,
      outstandingBalance,
      labourRevenue,
      partsRevenue,
      partsCostTotal,
      expensesTotal,
      netProfit,
      stockValuationCost,
      stockValuationRetail,
      activeJobsCount,
      completedJobsCount,
      todayJobsCount,
      weekJobsCount,
      monthJobsCount,
      overdueJobsCount,
      totalJobsCount: jobs.length,
      pendingEstimatesCount,
      lowStockCount,
      customersCount,
      employeesCount,
      upcomingAppointmentsCount: appointments.filter((a) => a.status !== 'CANCELLED').length,
      mechanicProductivity: Array.from(techStatsMap.values()),
      topVehicles,
      topParts,
      serviceReminders,
      weeklyJobs: [
        { day: 'M', count: weeklyCounts[0] },
        { day: 'T', count: weeklyCounts[1] },
        { day: 'W', count: weeklyCounts[2] },
        { day: 'T', count: weeklyCounts[3] },
        { day: 'F', count: weeklyCounts[4] },
        { day: 'S', count: weeklyCounts[5] },
      ],
      recentActivities: activities.slice(0, 6),
    });
  } catch (error) {
    console.error('Dashboard error:', error);
    res.status(500).json({ error: 'Failed to load dashboard metrics' });
  }
});

// ==========================================
// JOB CARDS API (7-Stage Workflow + Diagnostics + Warranty + Bay)
// ==========================================
app.get('/api/jobs', async (req: Request, res: Response) => {
  try {
    const { status, technician, search } = req.query;
    const whereClause: any = {};

    if (status && status !== 'All') {
      whereClause.status = String(status) as JobStatus;
    }
    if (technician && technician !== 'All') {
      whereClause.technician = String(technician);
    }

    const jobs = await prisma.jobCard.findMany({
      where: whereClause,
      include: {
        customer: true,
        vehicle: true,
        estimates: {
          include: { lineItems: true, invoice: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    if (search && String(search).trim() !== '') {
      const q = String(search).toLowerCase();
      const filtered = jobs.filter(
        (j) =>
          (j.jobNumber && j.jobNumber.toLowerCase().includes(q)) ||
          j.id.toLowerCase().includes(q) ||
          j.customer.name.toLowerCase().includes(q) ||
          j.vehicle.registrationNo.toLowerCase().includes(q) ||
          (j.vehicle.make && j.vehicle.make.toLowerCase().includes(q)) ||
          (j.vehicle.model && j.vehicle.model.toLowerCase().includes(q)) ||
          (((j as any).fuelType || j.vehicle.fuelType) && ((j as any).fuelType || j.vehicle.fuelType)!.toLowerCase().includes(q)) ||
          (j.workRequested && j.workRequested.toLowerCase().includes(q)) ||
          (j.bayNumber && j.bayNumber.toLowerCase().includes(q))
      );
      return res.json(filtered);
    }

    res.json(jobs);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch job cards' });
  }
});

app.post('/api/jobs', async (req: Request, res: Response) => {
  try {
    const {
      customerId,
      customerName,
      phone,
      email,
      address,
      category,
      taxPin,
      contactPerson,
      contactPhone,
      paymentTerms,
      registrationNo,
      make,
      model,
      year,
      color,
      engineNumber,
      fuelType,
      vinNumber,
      bodyType,
      fleetUnitNumber,
      assignedDriver,
      driverPhone,
      service,
      technician,
      bayNumber,
      priority,
      dueDate,
      status,
      odometer,
      fuelLevel,
      estimatedHours,
      actualHours,
      isWarranty,
      warrantyNotes,
      nextServiceMileage,
      nextServiceDate,
      walkAroundData,
    } = req.body;

    const clientCat = parseCategory(category);
    const cleanCustomerName = (customerName || 'Customer').trim();
    const cleanRegNo = (registrationNo || 'N/A').trim().toUpperCase();
    const cleanService = (service || 'General Service').trim();
    const dedupKey = `${cleanCustomerName.toLowerCase()}|${cleanRegNo}|${cleanService.toLowerCase()}`;

    // If an identical request is already in flight, await and return the same result
    if (inFlightJobCreations.has(dedupKey)) {
      const existingResult = await inFlightJobCreations.get(dedupKey);
      return res.status(201).json(existingResult);
    }

    const creationPromise = (async () => {
      const tenant = await getActiveTenant();

      // Check if an identical job card was just created within the last 15 seconds
      const recentCutoff = new Date(Date.now() - 15000);
      const recentDuplicate = await prisma.jobCard.findFirst({
        where: {
          tenantId: tenant.id,
          workRequested: cleanService,
          createdAt: { gte: recentCutoff },
          vehicle: {
            registrationNo: { equals: cleanRegNo, mode: 'insensitive' },
          },
        },
        include: {
          customer: true,
          vehicle: true,
          estimates: true,
        },
      });

      if (recentDuplicate) {
        return recentDuplicate;
      }

      let customer;
      if (customerId) {
        customer = await prisma.customer.findUnique({ where: { id: customerId } });
      }
      if (!customer) {
        customer = await prisma.customer.findFirst({
          where: {
            tenantId: tenant.id,
            name: { equals: cleanCustomerName, mode: 'insensitive' },
          },
        });
      }
      if (!customer) {
        customer = await prisma.customer.create({
          data: {
            name: cleanCustomerName,
            phone: phone || '',
            email: email || '',
            address: address || '',
            category: clientCat,
            taxPin: taxPin || null,
            contactPerson: contactPerson || null,
            contactPhone: contactPhone || null,
            paymentTerms: paymentTerms || null,
            tenantId: tenant.id,
          },
        });
      } else {
        customer = await prisma.customer.update({
          where: { id: customer.id },
          data: {
            ...(phone ? { phone } : {}),
            ...(email ? { email } : {}),
            ...(address ? { address } : {}),
            ...(category ? { category: clientCat } : {}),
            ...(taxPin ? { taxPin } : {}),
            ...(contactPerson ? { contactPerson } : {}),
            ...(contactPhone ? { contactPhone } : {}),
            ...(paymentTerms ? { paymentTerms } : {}),
          },
        });
      }

      // Check for vehicle by registration number across the entire tenant
      let vehicle = await prisma.vehicle.findFirst({
        where: {
          customer: { tenantId: tenant.id },
          registrationNo: { equals: cleanRegNo, mode: 'insensitive' },
        },
      });

      const parsedOdo = odometer ? Number(odometer) : null;
      let calculatedDaily: number | undefined = undefined;
      if (vehicle && vehicle.lastOdometer && vehicle.lastServiceDate && parsedOdo && parsedOdo > vehicle.lastOdometer) {
        const daysDiff = Math.max(1, Math.round((Date.now() - vehicle.lastServiceDate.getTime()) / (1000 * 60 * 60 * 24)));
        calculatedDaily = Math.round((parsedOdo - vehicle.lastOdometer) / daysDiff);
      }

      if (!vehicle) {
        vehicle = await prisma.vehicle.create({
          data: {
            registrationNo: cleanRegNo,
            make: make || '',
            model: model || '',
            year: year ? String(year) : null,
            color: color || null,
            engineNumber: engineNumber || null,
            fuelType: fuelType || 'Petrol',
            vinNumber: vinNumber || '',
            bodyType: bodyType || 'sedan',
            category: clientCat,
            fleetUnitNumber: fleetUnitNumber || null,
            assignedDriver: assignedDriver || null,
            driverPhone: driverPhone || null,
            lastOdometer: parsedOdo || 0,
            lastServiceDate: new Date(),
            nextServiceMileage: nextServiceMileage ? Number(nextServiceMileage) : null,
            nextServiceDate: nextServiceDate ? new Date(nextServiceDate) : null,
            customerId: customer.id,
          },
        });
      } else {
        vehicle = await prisma.vehicle.update({
          where: { id: vehicle.id },
          data: {
            ...(customerId || customer.id !== vehicle.customerId ? { customerId: customer.id } : {}),
            ...(make ? { make } : {}),
            ...(model ? { model } : {}),
            ...(year ? { year: String(year) } : {}),
            ...(color ? { color } : {}),
            ...(engineNumber ? { engineNumber } : {}),
            ...(fuelType ? { fuelType } : {}),
            ...(vinNumber ? { vinNumber } : {}),
            ...(bodyType ? { bodyType } : {}),
            ...(category ? { category: clientCat } : {}),
            ...(fleetUnitNumber ? { fleetUnitNumber } : {}),
            ...(assignedDriver ? { assignedDriver } : {}),
            ...(driverPhone ? { driverPhone } : {}),
            ...(parsedOdo ? { lastOdometer: parsedOdo } : {}),
            lastServiceDate: new Date(),
            ...(calculatedDaily !== undefined ? { avgDailyMileage: calculatedDaily } : {}),
            ...(nextServiceMileage ? { nextServiceMileage: Number(nextServiceMileage) } : {}),
            ...(nextServiceDate ? { nextServiceDate: new Date(nextServiceDate) } : {}),
          },
        });
      }

      const jobNumber = await generateJobNumber();

      return prisma.jobCard.create({
        data: {
          jobNumber,
          tenantId: tenant.id,
          customerId: customer.id,
          vehicleId: vehicle.id,
          workRequested: cleanService,
          technician: technician || 'Unassigned',
          bayNumber: bayNumber || 'Bay 1',
          priority: priority || 'Medium',
          dueDate: dueDate ? new Date(dueDate) : new Date(Date.now() + 2 * 86400000),
          status: (status as JobStatus) || 'IN_PROGRESS',
          odometer: odometer ? Number(odometer) : null,
          fuelType: fuelType || vehicle.fuelType || 'Petrol',
          fuelLevel: fuelLevel || null,
          estimatedHours: estimatedHours !== undefined ? Number(estimatedHours) : 2.0,
          actualHours: actualHours !== undefined ? Number(actualHours) : null,
          isWarranty: Boolean(isWarranty),
          warrantyNotes: warrantyNotes || null,
          nextServiceMileage: nextServiceMileage ? Number(nextServiceMileage) : null,
          nextServiceDate: nextServiceDate ? new Date(nextServiceDate) : null,
          walkAroundData: walkAroundData || undefined,
        },
        include: {
          customer: true,
          vehicle: true,
          estimates: true,
        },
      });
    })();

    inFlightJobCreations.set(dedupKey, creationPromise);
    try {
      const jobCard = await creationPromise;
      res.status(201).json(jobCard);
    } finally {
      setTimeout(() => inFlightJobCreations.delete(dedupKey), 3000);
    }
  } catch (error) {
    console.error('Create job error:', error);
    res.status(500).json({ error: 'Failed to create job card' });
  }
});

app.put('/api/jobs/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const {
      customerName,
      phone,
      registrationNo,
      make,
      model,
      year,
      color,
      engineNumber,
      fuelType,
      vinNumber,
      service,
      technician,
      bayNumber,
      priority,
      dueDate,
      status,
      odometer,
      fuelLevel,
      estimatedHours,
      actualHours,
      isWarranty,
      warrantyNotes,
      nextServiceMileage,
      nextServiceDate,
      walkAroundData,
    } = req.body;

    const existing = await prisma.jobCard.findUnique({
      where: { id },
      include: { customer: true, vehicle: true },
    });

    if (!existing) {
      return res.status(404).json({ error: 'Job Card not found' });
    }

    if (customerName || phone !== undefined) {
      await prisma.customer.update({
        where: { id: existing.customerId },
        data: {
          ...(customerName ? { name: customerName } : {}),
          ...(phone !== undefined ? { phone } : {}),
        },
      });
    }

    if (
      registrationNo ||
      make !== undefined ||
      model !== undefined ||
      year !== undefined ||
      color !== undefined ||
      engineNumber !== undefined ||
      fuelType !== undefined ||
      vinNumber !== undefined ||
      nextServiceMileage !== undefined ||
      nextServiceDate !== undefined
    ) {
      await prisma.vehicle.update({
        where: { id: existing.vehicleId },
        data: {
          ...(registrationNo ? { registrationNo } : {}),
          ...(make !== undefined ? { make } : {}),
          ...(model !== undefined ? { model } : {}),
          ...(year !== undefined ? { year: year ? String(year) : null } : {}),
          ...(color !== undefined ? { color } : {}),
          ...(engineNumber !== undefined ? { engineNumber } : {}),
          ...(fuelType !== undefined ? { fuelType } : {}),
          ...(vinNumber !== undefined ? { vinNumber } : {}),
          ...(nextServiceMileage !== undefined
            ? { nextServiceMileage: nextServiceMileage ? Number(nextServiceMileage) : null }
            : {}),
          ...(nextServiceDate !== undefined
            ? { nextServiceDate: nextServiceDate ? new Date(nextServiceDate) : null }
            : {}),
        },
      });
    }

    const updated = await prisma.jobCard.update({
      where: { id },
      data: {
        ...(service !== undefined ? { workRequested: service } : {}),
        ...(technician !== undefined ? { technician } : {}),
        ...(bayNumber !== undefined ? { bayNumber } : {}),
        ...(priority !== undefined ? { priority } : {}),
        ...(dueDate ? { dueDate: new Date(dueDate) } : {}),
        ...(status ? { status: status as JobStatus } : {}),
        ...(odometer !== undefined ? { odometer: odometer ? Number(odometer) : null } : {}),
        ...(fuelType !== undefined ? { fuelType } : {}),
        ...(fuelLevel !== undefined ? { fuelLevel } : {}),
        ...(estimatedHours !== undefined
          ? { estimatedHours: estimatedHours !== null ? Number(estimatedHours) : null }
          : {}),
        ...(actualHours !== undefined
          ? { actualHours: actualHours !== null ? Number(actualHours) : null }
          : {}),
        ...(isWarranty !== undefined ? { isWarranty: Boolean(isWarranty) } : {}),
        ...(warrantyNotes !== undefined ? { warrantyNotes } : {}),
        ...(nextServiceMileage !== undefined
          ? { nextServiceMileage: nextServiceMileage ? Number(nextServiceMileage) : null }
          : {}),
        ...(nextServiceDate !== undefined
          ? { nextServiceDate: nextServiceDate ? new Date(nextServiceDate) : null }
          : {}),
        ...(walkAroundData !== undefined ? { walkAroundData } : {}),
      },
      include: {
        customer: true,
        vehicle: true,
        estimates: { include: { lineItems: true, invoice: true } },
      },
    });

    res.json(updated);
  } catch (error) {
    console.error('Update job error:', error);
    res.status(500).json({ error: 'Failed to update job card' });
  }
});

app.delete('/api/jobs/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const estimates = await prisma.estimate.findMany({ where: { jobCardId: id } });
    for (const est of estimates) {
      await prisma.invoice.deleteMany({ where: { estimateId: est.id } });
      await prisma.estimateLineItem.deleteMany({ where: { estimateId: est.id } });
    }
    await prisma.estimate.deleteMany({ where: { jobCardId: id } });
    await prisma.jobCard.delete({ where: { id } });
    res.json({ success: true });
  } catch (error) {
    console.error('Delete job error:', error);
    res.status(500).json({ error: 'Failed to delete job card' });
  }
});

// ==========================================
// PARTS CATALOG & STOCK LEDGER API
// ==========================================
app.get('/api/parts', async (_req: Request, res: Response) => {
  try {
    const parts = await prisma.partCatalog.findMany({
      include: {
        stockMovements: {
          orderBy: { createdAt: 'desc' },
          take: 10,
        },
      },
      orderBy: { createdAt: 'desc' },
    });
    res.json(parts);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch parts catalog' });
  }
});

app.post('/api/parts', async (req: Request, res: Response) => {
  try {
    const {
      partNumber,
      description,
      brand,
      compatibility,
      costPrice,
      unitPrice,
      stockQuantity,
      reorderLevel,
      supplierName,
      supplierPhone,
      warrantyMonths,
    } = req.body;
    const tenant = await getActiveTenant();
    const initialQty = stockQuantity !== undefined ? Number(stockQuantity) : 10;
    const parsedCost = costPrice !== undefined ? Number(costPrice) : Number(unitPrice || 0) * 0.65;
    const parsedUnit = Number(unitPrice) || 0;

    const part = await prisma.partCatalog.create({
      data: {
        partNumber: partNumber || 'PART-001',
        description: description || 'Auto Part',
        brand: brand || null,
        compatibility: compatibility || null,
        costPrice: parsedCost,
        unitPrice: parsedUnit,
        stockQuantity: initialQty,
        reorderLevel: reorderLevel !== undefined ? Number(reorderLevel) : 5,
        supplierName: supplierName || null,
        supplierPhone: supplierPhone || null,
        warrantyMonths: warrantyMonths !== undefined ? Number(warrantyMonths) : 6,
        tenantId: tenant.id,
      },
    });

    if (initialQty > 0) {
      await prisma.stockMovement.create({
        data: {
          partId: part.id,
          type: 'RECEIVED',
          quantity: initialQty,
          unitCost: parsedCost,
          unitPrice: parsedUnit,
          supplierName: supplierName || null,
          reference: 'Initial Stock',
          notes: 'Initial catalog entry',
          tenantId: tenant.id,
        },
      });
    }

    res.status(201).json(part);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to create part' });
  }
});

app.put('/api/parts/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const {
      partNumber,
      description,
      brand,
      compatibility,
      costPrice,
      unitPrice,
      stockQuantity,
      reorderLevel,
      supplierName,
      supplierPhone,
      warrantyMonths,
    } = req.body;
    const part = await prisma.partCatalog.update({
      where: { id },
      data: {
        ...(partNumber !== undefined ? { partNumber } : {}),
        ...(description !== undefined ? { description } : {}),
        ...(brand !== undefined ? { brand } : {}),
        ...(compatibility !== undefined ? { compatibility } : {}),
        ...(costPrice !== undefined ? { costPrice: Number(costPrice) } : {}),
        ...(unitPrice !== undefined ? { unitPrice: Number(unitPrice) } : {}),
        ...(stockQuantity !== undefined ? { stockQuantity: Number(stockQuantity) } : {}),
        ...(reorderLevel !== undefined ? { reorderLevel: Number(reorderLevel) } : {}),
        ...(supplierName !== undefined ? { supplierName } : {}),
        ...(supplierPhone !== undefined ? { supplierPhone } : {}),
        ...(warrantyMonths !== undefined ? { warrantyMonths: Number(warrantyMonths) } : {}),
      },
    });
    res.json(part);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to update part' });
  }
});

app.post('/api/parts/:id/stock', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const { type = 'RECEIVED', quantity = 0, unitCost, unitPrice, supplierName, reference, notes, jobCardId } = req.body;
    const tenant = await getActiveTenant();
    const existing = await prisma.partCatalog.findUnique({ where: { id } });
    if (!existing) {
      return res.status(404).json({ error: 'Part not found' });
    }

    const qty = Number(quantity) || 0;
    let newStock = existing.stockQuantity;
    const movementType = String(type).toUpperCase();

    if (movementType === 'RECEIVED' || movementType === 'RETURNED') {
      newStock = existing.stockQuantity + qty;
    } else if (movementType === 'ISSUED') {
      newStock = Math.max(0, existing.stockQuantity - qty);
    } else if (movementType === 'ADJUSTED') {
      newStock = Math.max(0, qty);
    }

    const updatedPart = await prisma.partCatalog.update({
      where: { id },
      data: {
        stockQuantity: newStock,
        ...(unitCost !== undefined ? { costPrice: Number(unitCost) } : {}),
        ...(unitPrice !== undefined ? { unitPrice: Number(unitPrice) } : {}),
        ...(supplierName ? { supplierName } : {}),
      },
    });

    const movement = await prisma.stockMovement.create({
      data: {
        partId: id,
        type: movementType,
        quantity: qty,
        unitCost: unitCost !== undefined ? Number(unitCost) : existing.costPrice,
        unitPrice: unitPrice !== undefined ? Number(unitPrice) : existing.unitPrice,
        supplierName: supplierName || existing.supplierName,
        reference: reference || null,
        notes: notes || null,
        jobCardId: jobCardId || null,
        tenantId: tenant.id,
      },
    });

    res.json({ part: updatedPart, movement });
  } catch (error) {
    console.error('Stock adjustment error:', error);
    res.status(500).json({ error: 'Failed to record stock movement' });
  }
});

app.get('/api/stock-movements', async (_req: Request, res: Response) => {
  try {
    const movements = await prisma.stockMovement.findMany({
      include: { part: true },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    res.json(movements);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch stock movements' });
  }
});

app.delete('/api/parts/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    await prisma.stockMovement.deleteMany({ where: { partId: id } });
    await prisma.partCatalog.delete({ where: { id } });
    res.json({ success: true });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to delete part' });
  }
});

// ==========================================
// ESTIMATES API (PART vs LABOUR + Discount & 16% VAT logic)
// ==========================================
app.get('/api/estimates', async (_req: Request, res: Response) => {
  try {
    const estimates = await prisma.estimate.findMany({
      include: {
        lineItems: true,
        invoice: true,
        jobCard: {
          include: {
            customer: true,
            vehicle: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });
    res.json(estimates);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch estimates' });
  }
});

app.post('/api/estimates', async (req: Request, res: Response) => {
  try {
    const { jobCardId, items, discountRate = 20, taxRate = 16, status = 'DRAFT' } = req.body;

    if (!jobCardId) {
      return res.status(400).json({ error: 'A valid Job Card must be selected' });
    }

    const subtotal = (items || []).reduce((sum: number, item: any) => {
      return sum + Number(item.quantity) * Number(item.unitPrice);
    }, 0);

    const parsedDiscount = Number(discountRate) || 0;
    const parsedTax = Number(taxRate) || 16;

    const discountAmount = subtotal * (parsedDiscount / 100);
    const subtotalAfterDiscount = subtotal - discountAmount;
    const taxAmount = subtotalAfterDiscount * (parsedTax / 100);
    const total = subtotalAfterDiscount + taxAmount;

    const estimate = await prisma.estimate.create({
      data: {
        jobCardId,
        subtotal,
        discountRate: parsedDiscount,
        taxRate: parsedTax,
        total,
        status: status as EstimateStatus,
        lineItems: {
          create: (items || []).map((item: any) => ({
            description: item.description,
            itemType: item.itemType ? String(item.itemType).toUpperCase() : 'PART',
            partId: item.partId || null,
            quantity: Number(item.quantity),
            unitPrice: Number(item.unitPrice),
            total: Number(item.quantity) * Number(item.unitPrice),
          })),
        },
      },
      include: {
        lineItems: true,
        invoice: true,
        jobCard: { include: { customer: true, vehicle: true } },
      },
    });

    res.status(201).json(estimate);
  } catch (error) {
    console.error('Create estimate error:', error);
    res.status(500).json({ error: 'Failed to create estimate and calculate totals' });
  }
});

app.put('/api/estimates/:id/status', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const { status } = req.body;
    const estimate = await prisma.estimate.update({
      where: { id },
      data: { status: status as EstimateStatus },
      include: {
        lineItems: true,
        invoice: true,
        jobCard: { include: { customer: true, vehicle: true } },
      },
    });
    res.json(estimate);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to update estimate status' });
  }
});

app.delete('/api/estimates/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    await prisma.invoice.deleteMany({ where: { estimateId: id } });
    await prisma.estimateLineItem.deleteMany({ where: { estimateId: id } });
    await prisma.estimate.delete({ where: { id } });
    res.json({ success: true });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to delete estimate' });
  }
});

// ==========================================
// INVOICES API (Auto Stock Deduction + Deposits & Partial Payments)
// ==========================================
app.get('/api/invoices', async (_req: Request, res: Response) => {
  try {
    const invoices = await prisma.invoice.findMany({
      include: {
        estimate: {
          include: {
            lineItems: true,
            jobCard: {
              include: {
                customer: true,
                vehicle: true,
              },
            },
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });
    res.json(invoices);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch invoices' });
  }
});

app.post('/api/invoices', async (req: Request, res: Response) => {
  try {
    const {
      estimateId,
      paymentStatus = 'UNPAID',
      paymentMode = 'CASH',
      amountPaid: rawAmountPaid,
      mpesaReceiptNo,
    } = req.body;

    // Approve the estimate automatically when converting to an invoice
    const est = await prisma.estimate.update({
      where: { id: estimateId },
      data: { status: 'APPROVED' },
      include: { lineItems: true, jobCard: true },
    });

    const existing = await prisma.invoice.findUnique({
      where: { estimateId },
      include: {
        estimate: {
          include: {
            lineItems: true,
            jobCard: { include: { customer: true, vehicle: true } },
          },
        },
      },
    });
    if (existing) {
      return res.json(existing);
    }

    // Automatically deduct stock for PART line items on new invoice creation
    const tenant = await getActiveTenant();
    const allParts = await prisma.partCatalog.findMany();
    for (const item of est.lineItems || []) {
      if ((item.itemType || 'PART').toUpperCase() === 'LABOUR') continue;
      const matchedPart =
        (item.partId && allParts.find((p) => p.id === item.partId)) ||
        allParts.find(
          (p) =>
            item.description.toLowerCase().includes(p.partNumber.toLowerCase()) ||
            item.description.toLowerCase().includes(p.description.toLowerCase())
        );
      if (matchedPart) {
        const deductQty = Math.max(1, Math.round(item.quantity));
        const updatedQty = Math.max(0, matchedPart.stockQuantity - deductQty);
        matchedPart.stockQuantity = updatedQty;
        await prisma.partCatalog.update({
          where: { id: matchedPart.id },
          data: { stockQuantity: updatedQty },
        });
        await prisma.stockMovement.create({
          data: {
            partId: matchedPart.id,
            type: 'ISSUED',
            quantity: deductQty,
            unitCost: matchedPart.costPrice,
            unitPrice: item.unitPrice,
            reference: est.jobCard?.jobNumber || est.jobCardId,
            notes: `Auto-deducted on Invoice for ${est.jobCard?.jobNumber || 'Job'}`,
            jobCardId: est.jobCardId,
            tenantId: tenant.id,
          },
        });
      }
    }

    const total = est.total || 0;
    const initialPaid =
      paymentStatus === 'PAID'
        ? total
        : rawAmountPaid !== undefined
        ? Number(rawAmountPaid)
        : 0;
    const balanceDue = Math.max(0, total - initialPaid);
    const resolvedStatus: PaymentStatus =
      balanceDue <= 0 && total > 0
        ? 'PAID'
        : initialPaid > 0
        ? 'PARTIAL'
        : (paymentStatus as PaymentStatus);

    const paymentHistory =
      initialPaid > 0
        ? [
            {
              date: new Date().toISOString(),
              amount: initialPaid,
              mode: paymentMode || 'CASH',
              reference: mpesaReceiptNo || '',
              notes: resolvedStatus === 'PAID' ? 'Full Payment' : 'Initial Deposit',
            },
          ]
        : [];

    const invoice = await prisma.invoice.create({
      data: {
        estimateId,
        paymentStatus: resolvedStatus,
        paymentMode,
        amountPaid: initialPaid,
        balanceDue,
        mpesaReceiptNo: mpesaReceiptNo || null,
        paymentHistory,
      },
      include: {
        estimate: {
          include: {
            lineItems: true,
            jobCard: { include: { customer: true, vehicle: true } },
          },
        },
      },
    });

    res.status(201).json(invoice);
  } catch (error) {
    console.error('Create invoice error:', error);
    res.status(500).json({ error: 'Failed to generate invoice' });
  }
});

app.put('/api/invoices/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const {
      paymentStatus,
      paymentMode,
      paymentAmount,
      amountPaid: explicitAmountPaid,
      mpesaReceiptNo,
      notes,
    } = req.body;

    const existing = await prisma.invoice.findUnique({
      where: { id },
      include: { estimate: true },
    });
    if (!existing) {
      return res.status(404).json({ error: 'Invoice not found' });
    }

    const estTotal = existing.estimate?.total || 0;
    let newAmountPaid = existing.amountPaid || 0;
    const history: any[] = Array.isArray(existing.paymentHistory)
      ? [...(existing.paymentHistory as any[])]
      : [];

    if (paymentAmount !== undefined && Number(paymentAmount) > 0) {
      const added = Number(paymentAmount);
      newAmountPaid = Math.min(estTotal, newAmountPaid + added);
      history.push({
        date: new Date().toISOString(),
        amount: added,
        mode: paymentMode || existing.paymentMode || 'CASH',
        reference: mpesaReceiptNo || existing.mpesaReceiptNo || '',
        notes: notes || (newAmountPaid >= estTotal ? 'Balance Cleared' : 'Partial Payment / Deposit'),
      });
    } else if (explicitAmountPaid !== undefined) {
      newAmountPaid = Number(explicitAmountPaid);
    } else if (paymentStatus === 'PAID') {
      const remaining = Math.max(0, estTotal - newAmountPaid);
      newAmountPaid = estTotal;
      if (remaining > 0) {
        history.push({
          date: new Date().toISOString(),
          amount: remaining,
          mode: paymentMode || existing.paymentMode || 'CASH',
          reference: mpesaReceiptNo || existing.mpesaReceiptNo || '',
          notes: 'Full Payment',
        });
      }
    }

    const newBalanceDue = Math.max(0, estTotal - newAmountPaid);
    const resolvedStatus: PaymentStatus =
      newBalanceDue <= 0 && estTotal > 0
        ? 'PAID'
        : newAmountPaid > 0
        ? 'PARTIAL'
        : (paymentStatus as PaymentStatus) || existing.paymentStatus;

    const invoice = await prisma.invoice.update({
      where: { id },
      data: {
        paymentStatus: resolvedStatus,
        ...(paymentMode !== undefined ? { paymentMode } : {}),
        amountPaid: newAmountPaid,
        balanceDue: newBalanceDue,
        ...(mpesaReceiptNo !== undefined ? { mpesaReceiptNo } : {}),
        paymentHistory: history,
      },
      include: {
        estimate: {
          include: {
            lineItems: true,
            jobCard: { include: { customer: true, vehicle: true } },
          },
        },
      },
    });

    // If paid in full, mark job card as COMPLETED
    if (resolvedStatus === 'PAID' && invoice.estimate?.jobCardId) {
      await prisma.jobCard.update({
        where: { id: invoice.estimate.jobCardId },
        data: { status: 'COMPLETED' },
      });
    }

    res.json(invoice);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to update invoice' });
  }
});

// ==========================================
// CUSTOMERS, VEHICLE SERVICE HISTORY, APPOINTMENTS & EXPENSES API
// ==========================================
app.get('/api/customers', async (_req: Request, res: Response) => {
  try {
    // Clean up any orphaned duplicate customer/vehicle records that have 0 job cards
    const allCustomers = await prisma.customer.findMany({
      include: { vehicles: true, jobCards: true },
      orderBy: { createdAt: 'asc' },
    });
    const seenNames = new Set<string>();
    for (const c of allCustomers) {
      const key = c.name.trim().toLowerCase();
      if (seenNames.has(key) && c.jobCards.length === 0) {
        await prisma.vehicle.deleteMany({ where: { customerId: c.id } });
        await prisma.customer.delete({ where: { id: c.id } });
      } else {
        seenNames.add(key);
      }
    }

    const customers = await prisma.customer.findMany({
      include: {
        vehicles: true,
        jobCards: {
          include: {
            vehicle: true,
            estimates: {
              include: { lineItems: true, invoice: true },
            },
          },
          orderBy: { createdAt: 'desc' },
        },
      },
      orderBy: { createdAt: 'desc' },
    });
    res.json(customers);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch customers' });
  }
});

app.get('/api/customers/:id/history', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const customer = await prisma.customer.findUnique({
      where: { id },
      include: {
        vehicles: true,
        jobCards: {
          include: {
            vehicle: true,
            estimates: {
              include: { lineItems: true, invoice: true },
            },
          },
          orderBy: { createdAt: 'desc' },
        },
      },
    });
    if (!customer) {
      return res.status(404).json({ error: 'Customer not found' });
    }
    res.json(customer);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch customer service history' });
  }
});

app.post('/api/customers', async (req: Request, res: Response) => {
  try {
    const { name, phone, email, address, category, taxPin, contactPerson, contactPhone, paymentTerms } = req.body;
    const tenant = await getActiveTenant();
    const customer = await prisma.customer.create({
      data: {
        name,
        phone: phone || '',
        email: email || '',
        address: address || '',
        category: parseCategory(category),
        taxPin: taxPin || null,
        contactPerson: contactPerson || null,
        contactPhone: contactPhone || null,
        paymentTerms: paymentTerms || null,
        tenantId: tenant.id,
      },
      include: { vehicles: true, jobCards: true },
    });
    res.status(201).json(customer);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to create customer' });
  }
});

app.put('/api/customers/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const { name, phone, email, address, category, taxPin, contactPerson, contactPhone, paymentTerms } = req.body;
    const updated = await prisma.customer.update({
      where: { id },
      data: {
        ...(name !== undefined ? { name } : {}),
        ...(phone !== undefined ? { phone } : {}),
        ...(email !== undefined ? { email } : {}),
        ...(address !== undefined ? { address } : {}),
        ...(category !== undefined ? { category: parseCategory(category) } : {}),
        ...(taxPin !== undefined ? { taxPin } : {}),
        ...(contactPerson !== undefined ? { contactPerson } : {}),
        ...(contactPhone !== undefined ? { contactPhone } : {}),
        ...(paymentTerms !== undefined ? { paymentTerms } : {}),
      },
      include: { vehicles: true, jobCards: true },
    });
    res.json(updated);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to update customer' });
  }
});

// ==========================================
// VEHICLES & FLEET MANAGEMENT API
// ==========================================

// Fast Plate Auto-Lookup for Mobile & Web Receiving (Instant Autofill)
app.get('/api/vehicles/lookup', async (req: Request, res: Response) => {
  try {
    const rawPlate = String(req.query.q || '').trim();
    if (!rawPlate) {
      return res.status(400).json({ error: 'Search plate parameter "q" is required' });
    }

    const cleanPlate = rawPlate.toUpperCase();
    const compactPlate = cleanPlate.replace(/[\s\-_]/g, '');
    const tenant = await getActiveTenant();

    // Build flexible search terms: full input, stripped spaces, prefix and number
    const searchTerms = new Set<string>();
    searchTerms.add(cleanPlate);
    searchTerms.add(compactPlate);
    if (compactPlate.length >= 3) {
      searchTerms.add(compactPlate.substring(0, 3));
    }
    if (compactPlate.length >= 4) {
      searchTerms.add(compactPlate.substring(compactPlate.length - 4));
    }

    const orConditions = Array.from(searchTerms)
      .filter((t) => t.length >= 2)
      .map((term) => ({
        registrationNo: { contains: term, mode: 'insensitive' as const },
      }));

    // Search vehicles under active workshop tenant matching the plate
    const vehicles = await prisma.vehicle.findMany({
      where: {
        customer: { tenantId: tenant.id },
        OR: orConditions.length > 0 ? orConditions : [{ registrationNo: { contains: cleanPlate, mode: 'insensitive' } }],
      },
      include: {
        customer: true,
        jobCards: {
          orderBy: { createdAt: 'desc' },
          take: 3,
          include: {
            estimates: {
              include: { invoice: true, lineItems: true },
            },
          },
        },
      },
      take: 20,
    });

    // Try finding exact sanitized match first (ignoring spaces, hyphens, case)
    let matchedVehicle = vehicles.find(
      (v) => v.registrationNo.replace(/[\s\-_]/g, '').toUpperCase() === compactPlate
    );

    // Fallback to substring match or first found
    if (!matchedVehicle && vehicles.length > 0) {
      matchedVehicle = vehicles.find((v) =>
        v.registrationNo.replace(/[\s\-_]/g, '').toUpperCase().includes(compactPlate)
      ) || vehicles[0];
    }

    if (!matchedVehicle) {
      return res.json({ found: false, matches: [] });
    }

    const latestJob = matchedVehicle.jobCards[0] || null;
    const totalJobsCount = await prisma.jobCard.count({
      where: { vehicleId: matchedVehicle.id },
    });

    return res.json({
      found: true,
      vehicle: matchedVehicle,
      customer: matchedVehicle.customer,
      latestJob,
      totalJobsCount,
      matches: vehicles.map((v) => ({
        id: v.id,
        registrationNo: v.registrationNo,
        make: v.make,
        model: v.model,
        year: v.year,
        color: v.color,
        category: v.category,
        bodyType: v.bodyType,
        fuelType: v.fuelType,
        vinNumber: v.vinNumber,
        fleetUnitNumber: v.fleetUnitNumber,
        assignedDriver: v.assignedDriver,
        driverPhone: v.driverPhone,
        customerName: v.customer.name,
        customerPhone: v.customer.phone,
        lastOdometer: v.lastOdometer,
        lastServiceDate: v.lastServiceDate,
      })),
    });
  } catch (error) {
    console.error('Vehicle lookup error:', error);
    res.status(500).json({ error: 'Failed to look up vehicle' });
  }
});

// List Vehicles with Fleet Filters (PERSONAL, GOVERNMENT, SCHOOL, ORGANIZATION)
app.get('/api/vehicles', async (req: Request, res: Response) => {
  try {
    const tenant = await getActiveTenant();
    const { category, q, limit = '100', offset = '0' } = req.query;

    const whereClause: any = {
      customer: { tenantId: tenant.id },
    };

    if (category && String(category).toUpperCase() !== 'ALL') {
      whereClause.category = parseCategory(category);
    }

    if (q && String(q).trim() !== '') {
      const searchStr = String(q).trim();
      whereClause.OR = [
        { registrationNo: { contains: searchStr, mode: 'insensitive' } },
        { make: { contains: searchStr, mode: 'insensitive' } },
        { model: { contains: searchStr, mode: 'insensitive' } },
        { fleetUnitNumber: { contains: searchStr, mode: 'insensitive' } },
        { assignedDriver: { contains: searchStr, mode: 'insensitive' } },
        { vinNumber: { contains: searchStr, mode: 'insensitive' } },
        { customer: { name: { contains: searchStr, mode: 'insensitive' } } },
      ];
    }

    const [total, vehicles, personalCount, govCount, schoolCount, orgCount] = await Promise.all([
      prisma.vehicle.count({ where: whereClause }),
      prisma.vehicle.findMany({
        where: whereClause,
        include: {
          customer: true,
          _count: {
            select: { jobCards: true },
          },
        },
        orderBy: [{ lastServiceDate: 'desc' }, { updatedAt: 'desc' }],
        take: Math.min(200, Math.max(1, parseInt(String(limit), 10) || 100)),
        skip: Math.max(0, parseInt(String(offset), 10) || 0),
      }),
      prisma.vehicle.count({ where: { customer: { tenantId: tenant.id }, category: 'PERSONAL' } }),
      prisma.vehicle.count({ where: { customer: { tenantId: tenant.id }, category: 'GOVERNMENT' } }),
      prisma.vehicle.count({ where: { customer: { tenantId: tenant.id }, category: 'SCHOOL' } }),
      prisma.vehicle.count({ where: { customer: { tenantId: tenant.id }, category: 'ORGANIZATION' } }),
    ]);

    res.json({
      total,
      counts: {
        all: personalCount + govCount + schoolCount + orgCount,
        personal: personalCount,
        government: govCount,
        school: schoolCount,
        organization: orgCount,
      },
      vehicles: vehicles.map((v) => ({
        ...v,
        jobCardsCount: v._count.jobCards,
      })),
    });
  } catch (error) {
    console.error('List vehicles error:', error);
    res.status(500).json({ error: 'Failed to fetch vehicles' });
  }
});

// Single Vehicle Details
app.get('/api/vehicles/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const vehicle = await prisma.vehicle.findUnique({
      where: { id },
      include: {
        customer: true,
        jobCards: {
          orderBy: { createdAt: 'desc' },
          include: {
            estimates: {
              include: { invoice: true, lineItems: true },
            },
          },
        },
      },
    });

    if (!vehicle) {
      return res.status(404).json({ error: 'Vehicle not found' });
    }

    res.json(vehicle);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch vehicle' });
  }
});

// Full Vehicle Service Lifecycle & History Passport
app.get('/api/vehicles/:id/history', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const vehicle = await prisma.vehicle.findUnique({
      where: { id },
      include: {
        customer: true,
        jobCards: {
          include: {
            estimates: {
              include: {
                lineItems: true,
                invoice: true,
              },
            },
          },
          orderBy: { createdAt: 'desc' },
        },
      },
    });

    if (!vehicle) {
      return res.status(404).json({ error: 'Vehicle not found' });
    }

    // Calculate lifecycle analytics
    let totalSpend = 0;
    const partsReplaced: Array<{
      partName: string;
      quantity: number;
      price: number;
      date: Date;
      jobNumber: string;
    }> = [];

    const diagnosticHistory: Array<{
      date: Date;
      jobNumber: string;
      obdCodes?: string;
      defects?: string[];
      notes?: string;
    }> = [];

    const odometerTimeline: Array<{
      date: Date;
      odometer: number;
      jobNumber: string;
    }> = [];

    for (const jc of vehicle.jobCards) {
      if (jc.odometer) {
        odometerTimeline.push({
          date: jc.createdAt,
          odometer: jc.odometer,
          jobNumber: jc.jobNumber || 'N/A',
        });
      }

      if (jc.walkAroundData && typeof jc.walkAroundData === 'object') {
        const wad = jc.walkAroundData as any;
        if (wad.obdCodes || wad.scannerNotes || wad.defects || wad.itemsChecked) {
          diagnosticHistory.push({
            date: jc.createdAt,
            jobNumber: jc.jobNumber || 'N/A',
            obdCodes: wad.obdCodes || wad.scannerNotes || '',
            defects: Array.isArray(wad.defects) ? wad.defects : [],
            notes: wad.mechanicNotes || wad.generalNotes || '',
          });
        }
      }

      for (const est of jc.estimates) {
        if (est.invoice) {
          totalSpend += est.invoice.amountPaid > 0 ? est.invoice.amountPaid : est.total;
        } else if (est.status === 'APPROVED') {
          totalSpend += est.total;
        }

        for (const item of est.lineItems || []) {
          if ((item.itemType || 'PART').toUpperCase() !== 'LABOUR') {
            partsReplaced.push({
              partName: item.description,
              quantity: item.quantity,
              price: item.total,
              date: jc.createdAt,
              jobNumber: jc.jobNumber || 'N/A',
            });
          }
        }
      }
    }

    res.json({
      vehicle,
      customer: vehicle.customer,
      jobCards: vehicle.jobCards,
      summary: {
        totalVisits: vehicle.jobCards.length,
        totalSpend,
        currentOdometer: vehicle.lastOdometer || (odometerTimeline[0]?.odometer ?? 0),
        lastServiceDate: vehicle.lastServiceDate || vehicle.jobCards[0]?.createdAt || null,
        nextServiceMileage: vehicle.nextServiceMileage,
        nextServiceDate: vehicle.nextServiceDate,
      },
      odometerTimeline,
      partsReplaced,
      diagnosticHistory,
    });
  } catch (error) {
    console.error('Vehicle history error:', error);
    res.status(500).json({ error: 'Failed to fetch vehicle history' });
  }
});

// Update Vehicle Metadata (Fleet Unit, Driver, Body Type, Category, etc.)
app.put('/api/vehicles/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const {
      registrationNo,
      make,
      model,
      year,
      color,
      engineNumber,
      fuelType,
      vinNumber,
      bodyType,
      category,
      fleetUnitNumber,
      assignedDriver,
      driverPhone,
      lastOdometer,
      nextServiceMileage,
      nextServiceDate,
    } = req.body;

    const updated = await prisma.vehicle.update({
      where: { id },
      data: {
        ...(registrationNo ? { registrationNo: registrationNo.trim().toUpperCase() } : {}),
        ...(make !== undefined ? { make } : {}),
        ...(model !== undefined ? { model } : {}),
        ...(year !== undefined ? { year: String(year) } : {}),
        ...(color !== undefined ? { color } : {}),
        ...(engineNumber !== undefined ? { engineNumber } : {}),
        ...(fuelType !== undefined ? { fuelType } : {}),
        ...(vinNumber !== undefined ? { vinNumber } : {}),
        ...(bodyType !== undefined ? { bodyType } : {}),
        ...(category !== undefined ? { category: parseCategory(category) } : {}),
        ...(fleetUnitNumber !== undefined ? { fleetUnitNumber } : {}),
        ...(assignedDriver !== undefined ? { assignedDriver } : {}),
        ...(driverPhone !== undefined ? { driverPhone } : {}),
        ...(lastOdometer !== undefined ? { lastOdometer: Number(lastOdometer) } : {}),
        ...(nextServiceMileage !== undefined ? { nextServiceMileage: Number(nextServiceMileage) } : {}),
        ...(nextServiceDate !== undefined ? { nextServiceDate: new Date(nextServiceDate) } : {}),
      },
      include: { customer: true },
    });

    res.json(updated);
  } catch (error) {
    console.error('Update vehicle error:', error);
    res.status(500).json({ error: 'Failed to update vehicle' });
  }
});

// ==========================================
// APPOINTMENTS & BOOKING SCHEDULE API
// ==========================================
app.get('/api/appointments', async (_req: Request, res: Response) => {
  try {
    const appointments = await prisma.appointment.findMany({
      orderBy: { scheduledAt: 'asc' },
    });
    res.json(appointments);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch appointments' });
  }
});

app.post('/api/appointments', async (req: Request, res: Response) => {
  try {
    const {
      customerName,
      phone,
      customerPhone,
      registrationNo,
      makeModel,
      serviceType,
      scheduledAt,
      assignedBay,
      bayNumber,
      technician,
      status,
      notes,
    } = req.body;
    const tenant = await getActiveTenant();
    const appointment = await prisma.appointment.create({
      data: {
        customerName: customerName || 'Walk-in Customer',
        phone: phone || customerPhone || '',
        registrationNo: (registrationNo || 'TBA').toUpperCase(),
        makeModel: makeModel || '',
        serviceType: serviceType || 'General Service',
        scheduledAt: scheduledAt ? new Date(scheduledAt) : new Date(Date.now() + 86400000),
        assignedBay: assignedBay || bayNumber || 'Bay 1',
        technician: technician || 'Unassigned',
        status: status || 'SCHEDULED',
        notes: notes || null,
        tenantId: tenant.id,
      },
    });
    res.status(201).json(appointment);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to create appointment' });
  }
});

app.put('/api/appointments/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const {
      customerName,
      phone,
      customerPhone,
      registrationNo,
      makeModel,
      serviceType,
      scheduledAt,
      assignedBay,
      bayNumber,
      technician,
      status,
      notes,
    } = req.body;
    const updated = await prisma.appointment.update({
      where: { id },
      data: {
        ...(customerName !== undefined ? { customerName } : {}),
        ...(phone !== undefined || customerPhone !== undefined ? { phone: phone ?? customerPhone } : {}),
        ...(registrationNo !== undefined ? { registrationNo } : {}),
        ...(makeModel !== undefined ? { makeModel } : {}),
        ...(serviceType !== undefined ? { serviceType } : {}),
        ...(scheduledAt ? { scheduledAt: new Date(scheduledAt) } : {}),
        ...(assignedBay !== undefined || bayNumber !== undefined ? { assignedBay: assignedBay ?? bayNumber } : {}),
        ...(technician !== undefined ? { technician } : {}),
        ...(status !== undefined ? { status } : {}),
        ...(notes !== undefined ? { notes } : {}),
      },
    });
    res.json(updated);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to update appointment' });
  }
});

app.delete('/api/appointments/:id', async (req: Request, res: Response) => {
  try {
    await prisma.appointment.delete({ where: { id: String(req.params.id) } });
    res.json({ success: true });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to delete appointment' });
  }
});

// ==========================================
// WORKSHOP EXPENSES API (For Net Profit Reporting)
// ==========================================
app.get('/api/expenses', async (_req: Request, res: Response) => {
  try {
    const expenses = await prisma.expense.findMany({
      orderBy: { incurredAt: 'desc' },
    });
    res.json(expenses);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch expenses' });
  }
});

app.post('/api/expenses', async (req: Request, res: Response) => {
  try {
    const { category, description, amount, paymentMode, reference, incurredAt } = req.body;
    const tenant = await getActiveTenant();
    const expense = await prisma.expense.create({
      data: {
        category: category || 'Workshop Consumables',
        description: description || 'Expense',
        amount: Number(amount) || 0,
        paymentMode: paymentMode || 'CASH',
        reference: reference || null,
        incurredAt: incurredAt ? new Date(incurredAt) : new Date(),
        tenantId: tenant.id,
      },
    });
    res.status(201).json(expense);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to record expense' });
  }
});

app.delete('/api/expenses/:id', async (req: Request, res: Response) => {
  try {
    await prisma.expense.delete({ where: { id: String(req.params.id) } });
    res.json({ success: true });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to delete expense' });
  }
});

// ==========================================
// AUTHENTICATION & SESSION APIS
// ==========================================

// Login with User ID / Email / Username / Phone + Password
app.post('/api/auth/login', async (req: Request, res: Response) => {
  try {
    const { identifier, password } = req.body;
    if (!identifier || !password) {
      return res.status(400).json({ error: 'Please enter your User ID or Email, and your password.' });
    }

    const trimmed = String(identifier).trim();
    const tenant = await getActiveTenant();

    // Check if user exists by email, username, phone, or UUID id
    const user = await prisma.user.findFirst({
      where: {
        tenantId: tenant.id,
        OR: [
          { email: { equals: trimmed, mode: 'insensitive' } },
          { username: { equals: trimmed, mode: 'insensitive' } },
          { phone: { equals: trimmed } },
          { id: { equals: trimmed } },
        ],
      },
    });

    if (!user) {
      return res.status(401).json({ error: 'Invalid User ID / Email or password.' });
    }

    if (!user.isActive) {
      return res.status(403).json({ error: 'This user account has been deactivated. Please contact the Workshop Owner.' });
    }

    // Verify password hash
    let passwordMatches = false;
    if (user.password.startsWith('$2a$') || user.password.startsWith('$2b$')) {
      passwordMatches = await comparePassword(password, user.password);
    } else {
      // Automatic upgrade for legacy plain text passwords if any
      passwordMatches = user.password === password;
      if (passwordMatches) {
        const newHash = await hashPassword(password);
        await prisma.user.update({ where: { id: user.id }, data: { password: newHash } });
      }
    }

    if (!passwordMatches) {
      return res.status(401).json({ error: 'Invalid User ID / Email or password.' });
    }

    const token = generateToken(user);

    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        name: user.name,
        phone: user.phone,
        role: user.role,
        specialization: user.specialization,
        commissionRate: user.commissionRate,
        tenantId: user.tenantId,
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Login failed due to a server error.' });
  }
});

// Get current logged-in user profile
app.get('/api/auth/me', async (req: Request, res: Response) => {
  try {
    if (!req.user || req.user.id === 'system-actor') {
      return res.status(401).json({ error: 'Not authenticated.' });
    }
    const user = await prisma.user.findUnique({
      where: { id: req.user.id },
      select: {
        id: true,
        email: true,
        username: true,
        name: true,
        phone: true,
        role: true,
        specialization: true,
        commissionRate: true,
        isActive: true,
        tenantId: true,
        createdAt: true,
      },
    });
    if (!user || !user.isActive) {
      return res.status(401).json({ error: 'User account not found or deactivated.' });
    }
    res.json({ user });
  } catch (error) {
    console.error('Auth me error:', error);
    res.status(500).json({ error: 'Failed to fetch user profile.' });
  }
});

// Logout
app.post('/api/auth/logout', (_req: Request, res: Response) => {
  res.json({ success: true, message: 'Logged out successfully.' });
});

// Change own password
app.post('/api/auth/change-password', async (req: Request, res: Response) => {
  try {
    if (!req.user || req.user.id === 'system-actor') {
      return res.status(401).json({ error: 'Authentication required.' });
    }
    const { oldPassword, newPassword } = req.body;
    if (!oldPassword || !newPassword || newPassword.length < 6) {
      return res.status(400).json({ error: 'New password must be at least 6 characters long.' });
    }
    const user = await prisma.user.findUnique({ where: { id: req.user.id } });
    if (!user) return res.status(404).json({ error: 'User not found.' });

    const ok = await comparePassword(oldPassword, user.password);
    if (!ok) return res.status(400).json({ error: 'Incorrect current password.' });

    const newHash = await hashPassword(newPassword);
    await prisma.user.update({ where: { id: user.id }, data: { password: newHash } });
    res.json({ success: true, message: 'Password updated successfully.' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to change password.' });
  }
});

// ==========================================
// WORKSHOP OWNER: USER & TEAM MANAGEMENT APIS
// ==========================================

// Get all workshop users/staff
app.get('/api/users', async (req: Request, res: Response) => {
  try {
    const tenant = await getActiveTenant();
    const users = await prisma.user.findMany({
      where: { tenantId: tenant.id },
      select: {
        id: true,
        email: true,
        username: true,
        name: true,
        phone: true,
        role: true,
        specialization: true,
        commissionRate: true,
        isActive: true,
        createdAt: true,
        updatedAt: true,
      },
      orderBy: { createdAt: 'desc' },
    });
    res.json(users);
  } catch (error) {
    console.error('Fetch users error:', error);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

// Workshop owner creates new user
app.post('/api/users', async (req: Request, res: Response) => {
  try {
    const { name, email, username, phone, password, role, specialization, commissionRate } = req.body;
    if (!name || !email || !password) {
      return res.status(400).json({ error: 'Name, email, and initial password are required.' });
    }

    const tenant = await getActiveTenant();
    const cleanEmail = String(email).trim().toLowerCase();
    const cleanUsername = username ? String(username).trim().toLowerCase() : null;

    const existing = await prisma.user.findFirst({
      where: {
        OR: [
          { email: cleanEmail },
          ...(cleanUsername ? [{ username: cleanUsername }] : []),
        ],
      },
    });
    if (existing) {
      return res.status(409).json({ error: 'A user with that email or username already exists.' });
    }

    const hashedPassword = await hashPassword(password);
    const validRole = Object.values(Role).includes(role as Role) ? (role as Role) : 'MECHANIC';

    const newUser = await prisma.user.create({
      data: {
        name: String(name).trim(),
        email: cleanEmail,
        username: cleanUsername,
        phone: phone ? String(phone).trim() : null,
        password: hashedPassword,
        role: validRole,
        specialization: specialization ? String(specialization).trim() : null,
        commissionRate: typeof commissionRate === 'number' ? commissionRate : (Number(commissionRate) || 0),
        isActive: true,
        tenantId: tenant.id,
      },
      select: {
        id: true,
        email: true,
        username: true,
        name: true,
        phone: true,
        role: true,
        specialization: true,
        commissionRate: true,
        isActive: true,
        createdAt: true,
      },
    });

    res.status(201).json(newUser);
  } catch (error) {
    console.error('Create user error:', error);
    res.status(500).json({ error: 'Failed to create user.' });
  }
});

// Update user details
app.put('/api/users/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { name, email, username, phone, role, specialization, commissionRate, isActive } = req.body;

    const data: any = {};
    if (name !== undefined) data.name = String(name).trim();
    if (email !== undefined) data.email = String(email).trim().toLowerCase();
    if (username !== undefined) data.username = username ? String(username).trim().toLowerCase() : null;
    if (phone !== undefined) data.phone = phone ? String(phone).trim() : null;
    if (role !== undefined && Object.values(Role).includes(role as Role)) data.role = role as Role;
    if (specialization !== undefined) data.specialization = specialization ? String(specialization).trim() : null;
    if (commissionRate !== undefined) data.commissionRate = Number(commissionRate) || 0;
    if (isActive !== undefined) data.isActive = Boolean(isActive);

    const updated = await prisma.user.update({
      where: { id: String(id) },
      data,
      select: {
        id: true,
        email: true,
        username: true,
        name: true,
        phone: true,
        role: true,
        specialization: true,
        commissionRate: true,
        isActive: true,
        updatedAt: true,
      },
    });

    res.json(updated);
  } catch (error) {
    console.error('Update user error:', error);
    res.status(500).json({ error: 'Failed to update user.' });
  }
});

// Owner resets user password
app.post('/api/users/:id/reset-password', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { newPassword } = req.body;
    if (!newPassword || newPassword.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters.' });
    }
    const hash = await hashPassword(newPassword);
    await prisma.user.update({
      where: { id: String(id) },
      data: { password: hash },
    });
    res.json({ success: true, message: 'Password reset successfully.' });
  } catch (error) {
    console.error('Reset password error:', error);
    res.status(500).json({ error: 'Failed to reset password.' });
  }
});

// Deactivate / delete user
app.delete('/api/users/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    // Don't let owner delete own account if they are the only owner
    await prisma.user.update({
      where: { id: String(id) },
      data: { isActive: false },
    });
    res.json({ success: true, message: 'User deactivated successfully.' });
  } catch (error) {
    console.error('Delete user error:', error);
    res.status(500).json({ error: 'Failed to deactivate user.' });
  }
});

// Backward-compatible endpoints for /api/employees
app.get('/api/employees', async (req: Request, res: Response) => {
  try {
    const tenant = await getActiveTenant();
    const users = await prisma.user.findMany({
      where: { tenantId: tenant.id, isActive: true },
      select: {
        id: true,
        email: true,
        username: true,
        name: true,
        phone: true,
        role: true,
        specialization: true,
        commissionRate: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'desc' },
    });
    res.json(users);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch employees' });
  }
});

app.post('/api/employees', async (req: Request, res: Response) => {
  try {
    const { name, email, role, password, username, phone } = req.body;
    const tenant = await getActiveTenant();
    const cleanEmail = email || `${name.toLowerCase().replace(/\s+/g, '.')}.${Date.now()}@workshop.com`;
    const cleanPassword = password || 'password123';
    const hashedPassword = await hashPassword(cleanPassword);
    const validRole = Object.values(Role).includes(role as Role) ? (role as Role) : 'MECHANIC';

    const user = await prisma.user.create({
      data: {
        name,
        email: cleanEmail,
        username: username || null,
        phone: phone || null,
        password: hashedPassword,
        role: validRole,
        tenantId: tenant.id,
      },
    });
    res.status(201).json(user);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to create employee' });
  }
});

app.delete('/api/employees/:id', async (req: Request, res: Response) => {
  try {
    await prisma.user.update({ where: { id: String(req.params.id) }, data: { isActive: false } });
    res.json({ success: true });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to delete employee' });
  }
});

app.get('/api/settings', async (_req: Request, res: Response) => {
  try {
    const tenant = await getActiveTenant();
    res.json(tenant);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch settings' });
  }
});

app.put('/api/settings', async (req: Request, res: Response) => {
  try {
    const tenant = await getActiveTenant();
    const { name, address, taxPin, logoUrl } = req.body;
    const updated = await prisma.tenant.update({
      where: { id: tenant.id },
      data: {
        ...(name !== undefined ? { name } : {}),
        ...(address !== undefined ? { address } : {}),
        ...(taxPin !== undefined ? { taxPin } : {}),
        ...(logoUrl !== undefined ? { logoUrl } : {}),
      },
    });
    res.json(updated);
  } catch (error) {
    res.status(500).json({ error: 'Failed to update settings' });
  }
});

// ==========================================
// NEON OBJECT STORAGE (ASSETS BUCKET) API
// ==========================================

app.post('/api/assets/upload', async (req: Request, res: Response) => {
  try {
    const { key, contentBase64, contentText, contentType, isWorkshopLogo, jobCardId } = req.body;
    if (!key) {
      res.status(400).json({ error: 'Object key is required' });
      return;
    }

    const body: Buffer | string = contentBase64
      ? Buffer.from(String(contentBase64), 'base64')
      : String(contentText ?? '');

    const { presignedUrl } = await uploadWorkshopAsset(
      String(key),
      body,
      contentType ? String(contentType) : 'application/octet-stream'
    );

    // Canonical Neon pattern: store the bucket key in Lakebase Postgres and presign on read
    if (isWorkshopLogo) {
      const tenant = await getActiveTenant();
      await prisma.tenant.update({
        where: { id: tenant.id },
        data: { logoUrl: String(key) },
      });
    }

    if (jobCardId) {
      const existingJob = await prisma.jobCard.findUnique({ where: { id: String(jobCardId) } });
      if (existingJob) {
        const currentWalkAround =
          existingJob.walkAroundData && typeof existingJob.walkAroundData === 'object'
            ? (existingJob.walkAroundData as Record<string, unknown>)
            : {};
        const currentAssets = Array.isArray(currentWalkAround.assetKeys)
          ? (currentWalkAround.assetKeys as string[])
          : [];
        await prisma.jobCard.update({
          where: { id: existingJob.id },
          data: {
            walkAroundData: {
              ...currentWalkAround,
              assetKeys: Array.from(new Set([...currentAssets, String(key)])),
            },
          },
        });
      }
    }

    res.status(201).json({
      bucket: ASSETS_BUCKET,
      branch: process.env.NEON_BRANCH || 'production',
      key: String(key),
      presignedUrl,
    });
  } catch (error: any) {
    console.error('Object storage upload error:', error);
    res.status(500).json({ error: 'Failed to upload asset to Neon Object Storage', details: error?.message });
  }
});

app.get('/api/assets/presign', async (req: Request, res: Response) => {
  try {
    const key = String(req.query.key || '');
    if (!key) {
      res.status(400).json({ error: 'Query param ?key= is required' });
      return;
    }
    const exists = await workshopAssetExists(key);
    if (!exists) {
      res.status(404).json({ error: 'Asset not found in Neon Object Storage', key, exists: false });
      return;
    }
    const presignedUrl = await getWorkshopAssetPresignedUrl(key, 3600);
    res.json({
      bucket: ASSETS_BUCKET,
      branch: process.env.NEON_BRANCH || 'production',
      key,
      exists,
      presignedUrl,
    });
  } catch (error: any) {
    console.error('Object storage presign error:', error);
    res.status(500).json({ error: 'Failed to presign asset URL', details: error?.message });
  }
});

app.get('/api/assets/download', async (req: Request, res: Response) => {
  try {
    const key = String(req.query.key || '');
    if (!key) {
      res.status(400).json({ error: 'Query param ?key= is required' });
      return;
    }
    const bytes = await downloadWorkshopAsset(key);
    res.setHeader('Content-Type', 'application/octet-stream');
    res.send(Buffer.from(bytes));
  } catch (error: any) {
    console.error('Object storage download error:', error);
    res.status(500).json({ error: 'Failed to download asset from Neon Object Storage', details: error?.message });
  }
});

app.delete('/api/assets', async (req: Request, res: Response) => {
  try {
    const key = String(req.query.key || '');
    if (!key) {
      res.status(400).json({ error: 'Query param ?key= is required' });
      return;
    }
    await deleteWorkshopAsset(key);
    res.json({ deleted: true, bucket: ASSETS_BUCKET, key });
  } catch (error: any) {
    console.error('Object storage delete error:', error);
    res.status(500).json({ error: 'Failed to delete asset from Neon Object Storage', details: error?.message });
  }
});

// Serve compiled Flutter Web App at root (https://auto.zksms.online/)
const publicWebDir = path.resolve(__dirname, '../public');
app.use(express.static(publicWebDir));
app.get(/^(?!\/api).*/, (_req: Request, res: Response) => {
  res.sendFile(path.join(publicWebDir, 'index.html'), (err) => {
    if (err) {
      res.status(200).send('Auto Repair Workshop API is running at /api');
    }
  });
});

app.listen(PORT, async () => {
  try {
    const tenant = await getActiveTenant();
    await seedInitialOwner(prisma, tenant.id);
  } catch (err) {
    console.error('Startup owner seed check error:', err);
  }
  console.log(`Server is running on http://localhost:${PORT} (Neon branch: ${process.env.NEON_BRANCH || 'linked'})`);
});
