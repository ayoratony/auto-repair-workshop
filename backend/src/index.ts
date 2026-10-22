import path from 'path';
import express, { Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { PrismaClient, JobStatus, EstimateStatus, PaymentStatus, Role } from '@prisma/client';
import {
  ASSETS_BUCKET,
  uploadWorkshopAsset,
  downloadWorkshopAsset,
  getWorkshopAssetPresignedUrl,
  workshopAssetExists,
  deleteWorkshopAsset,
} from './storage';

dotenv.config({ path: path.resolve(__dirname, '../../.env.local') });
dotenv.config();

const app = express();
const prisma = new PrismaClient();
const PORT = Number(process.env.PORT) || 5001;

app.use(cors());
app.use(express.json());

// Helper to get or create the active workshop tenant
async function getActiveTenant() {
  let tenant = await prisma.tenant.findFirst();
  if (!tenant) {
    tenant = await prisma.tenant.create({
      data: {
        name: 'MechanicHQ Auto Workshop',
        address: 'Industrial Area, Nairobi',
        taxPin: 'P051234567X',
      },
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
    ] = await Promise.all([
      prisma.jobCard.findMany({
        include: { customer: true, vehicle: true },
        orderBy: { updatedAt: 'desc' },
      }),
      prisma.estimate.findMany({
        include: { jobCard: { include: { customer: true, vehicle: true } }, invoice: true },
        orderBy: { updatedAt: 'desc' },
      }),
      prisma.invoice.findMany({
        include: { estimate: { include: { jobCard: { include: { customer: true, vehicle: true } } } } },
        orderBy: { updatedAt: 'desc' },
      }),
      prisma.partCatalog.findMany(),
      prisma.customer.count(),
      prisma.user.count(),
    ]);

    // Calculate Total Revenue from PAID/PARTIAL invoices, or fallback to APPROVED estimates
    let totalRevenue = 0;
    for (const inv of invoices) {
      if (inv.paymentStatus === 'PAID' && inv.estimate) {
        totalRevenue += inv.estimate.total;
      }
    }
    if (totalRevenue === 0) {
      for (const est of estimates) {
        if (est.status === 'APPROVED') {
          totalRevenue += est.total;
        }
      }
    }

    const activeJobsCount = jobs.filter((j) => j.status !== 'COMPLETED').length;
    const completedJobsCount = jobs.filter((j) => j.status === 'COMPLETED').length;
    const pendingEstimatesCount = estimates.filter((e) => e.status === 'DRAFT' || e.status === 'SENT').length;
    const lowStockCount = parts.filter((p) => p.stockQuantity <= 5).length;

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
      activeJobsCount,
      completedJobsCount,
      totalJobsCount: jobs.length,
      pendingEstimatesCount,
      lowStockCount,
      customersCount,
      employeesCount,
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
// JOB CARDS API
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
          (j.workRequested && j.workRequested.toLowerCase().includes(q))
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
      registrationNo,
      make,
      model,
      vinNumber,
      service,
      technician,
      priority,
      dueDate,
      status,
      odometer,
      fuelLevel,
      walkAroundData,
    } = req.body;

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
            tenantId: tenant.id,
          },
        });
      } else if (phone || email || address) {
        customer = await prisma.customer.update({
          where: { id: customer.id },
          data: {
            ...(phone ? { phone } : {}),
            ...(email ? { email } : {}),
            ...(address ? { address } : {}),
          },
        });
      }

      let vehicle = await prisma.vehicle.findFirst({
        where: {
          customerId: customer.id,
          registrationNo: { equals: cleanRegNo, mode: 'insensitive' },
        },
      });

      if (!vehicle) {
        vehicle = await prisma.vehicle.create({
          data: {
            registrationNo: cleanRegNo,
            make: make || '',
            model: model || '',
            vinNumber: vinNumber || '',
            customerId: customer.id,
          },
        });
      } else if (make || model || vinNumber) {
        vehicle = await prisma.vehicle.update({
          where: { id: vehicle.id },
          data: {
            ...(make ? { make } : {}),
            ...(model ? { model } : {}),
            ...(vinNumber ? { vinNumber } : {}),
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
          priority: priority || 'Medium',
          dueDate: dueDate ? new Date(dueDate) : new Date(Date.now() + 2 * 86400000),
          status: (status as JobStatus) || 'IN_PROGRESS',
          odometer: odometer ? Number(odometer) : null,
          fuelLevel: fuelLevel || null,
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
      service,
      technician,
      priority,
      dueDate,
      status,
      odometer,
      fuelLevel,
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

    if (registrationNo || make !== undefined || model !== undefined) {
      await prisma.vehicle.update({
        where: { id: existing.vehicleId },
        data: {
          ...(registrationNo ? { registrationNo } : {}),
          ...(make !== undefined ? { make } : {}),
          ...(model !== undefined ? { model } : {}),
        },
      });
    }

    const updated = await prisma.jobCard.update({
      where: { id },
      data: {
        ...(service !== undefined ? { workRequested: service } : {}),
        ...(technician !== undefined ? { technician } : {}),
        ...(priority !== undefined ? { priority } : {}),
        ...(dueDate ? { dueDate: new Date(dueDate) } : {}),
        ...(status ? { status: status as JobStatus } : {}),
        ...(odometer !== undefined ? { odometer: odometer ? Number(odometer) : null } : {}),
        ...(fuelLevel !== undefined ? { fuelLevel } : {}),
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
// PARTS CATALOG API
// ==========================================
app.get('/api/parts', async (_req: Request, res: Response) => {
  try {
    const parts = await prisma.partCatalog.findMany({
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
    const { partNumber, description, unitPrice, stockQuantity } = req.body;
    const tenant = await getActiveTenant();
    const part = await prisma.partCatalog.create({
      data: {
        partNumber: partNumber || 'PART-001',
        description: description || 'Auto Part',
        unitPrice: Number(unitPrice) || 0,
        stockQuantity: stockQuantity !== undefined ? Number(stockQuantity) : 10,
        tenantId: tenant.id,
      },
    });
    res.status(201).json(part);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to create part' });
  }
});

app.put('/api/parts/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const { partNumber, description, unitPrice, stockQuantity } = req.body;
    const part = await prisma.partCatalog.update({
      where: { id },
      data: {
        ...(partNumber !== undefined ? { partNumber } : {}),
        ...(description !== undefined ? { description } : {}),
        ...(unitPrice !== undefined ? { unitPrice: Number(unitPrice) } : {}),
        ...(stockQuantity !== undefined ? { stockQuantity: Number(stockQuantity) } : {}),
      },
    });
    res.json(part);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to update part' });
  }
});

app.delete('/api/parts/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    await prisma.partCatalog.delete({ where: { id } });
    res.json({ success: true });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to delete part' });
  }
});

// ==========================================
// ESTIMATES API (Discount & 16% VAT logic)
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
// INVOICES API
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
    const { estimateId, paymentStatus = 'UNPAID', paymentMode = 'CASH' } = req.body;

    // Approve the estimate automatically when converting to an invoice
    await prisma.estimate.update({
      where: { id: estimateId },
      data: { status: 'APPROVED' },
    });

    const existing = await prisma.invoice.findUnique({ where: { estimateId } });
    if (existing) {
      return res.json(existing);
    }

    const invoice = await prisma.invoice.create({
      data: {
        estimateId,
        paymentStatus: paymentStatus as PaymentStatus,
        paymentMode,
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
    const { paymentStatus, paymentMode } = req.body;
    const invoice = await prisma.invoice.update({
      where: { id },
      data: {
        ...(paymentStatus ? { paymentStatus: paymentStatus as PaymentStatus } : {}),
        ...(paymentMode !== undefined ? { paymentMode } : {}),
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

    // If paid, mark job card as COMPLETED
    if (paymentStatus === 'PAID') {
      const est = await prisma.estimate.findUnique({ where: { id: invoice.estimateId } });
      if (est?.jobCardId) {
        await prisma.jobCard.update({
          where: { id: est.jobCardId },
          data: { status: 'COMPLETED' },
        });
      }
    }

    res.json(invoice);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to update invoice' });
  }
});

// ==========================================
// CUSTOMERS & EMPLOYEES & SETTINGS API
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
        jobCards: true,
      },
      orderBy: { createdAt: 'desc' },
    });
    res.json(customers);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch customers' });
  }
});

app.post('/api/customers', async (req: Request, res: Response) => {
  try {
    const { name, phone, email, address } = req.body;
    const tenant = await getActiveTenant();
    const customer = await prisma.customer.create({
      data: {
        name,
        phone: phone || '',
        email: email || '',
        address: address || '',
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

app.get('/api/employees', async (_req: Request, res: Response) => {
  try {
    const users = await prisma.user.findMany({
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
    const { name, email, role } = req.body;
    const tenant = await getActiveTenant();
    const user = await prisma.user.create({
      data: {
        name,
        email: email || `${name.toLowerCase().replace(/\s+/g, '.')}.${Date.now()}@workshop.com`,
        password: 'hashed_password',
        role: (role as Role) || 'MECHANIC',
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
    await prisma.user.delete({ where: { id: String(req.params.id) } });
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

app.listen(PORT, () => {
  console.log(`Server is running on http://localhost:${PORT} (Neon branch: ${process.env.NEON_BRANCH || 'linked'})`);
});
