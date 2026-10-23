import { Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { PrismaClient, Role, User } from '@prisma/client';

const JWT_SECRET = process.env.JWT_SECRET || 'autoke-workshop-jwt-secret-key-2026';
const TOKEN_EXPIRY = '7d';

export interface AuthUserPayload {
  id: string;
  email: string;
  username?: string | null;
  name: string;
  phone?: string | null;
  role: Role;
  tenantId: string;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthUserPayload;
    }
  }
}

export async function hashPassword(plainText: string): Promise<string> {
  return bcrypt.hash(plainText, 10);
}

export async function comparePassword(plainText: string, hash: string): Promise<boolean> {
  return bcrypt.compare(plainText, hash);
}

export function generateToken(user: User): string {
  const payload: AuthUserPayload = {
    id: user.id,
    email: user.email,
    username: user.username,
    name: user.name,
    phone: user.phone,
    role: user.role,
    tenantId: user.tenantId,
  };
  return jwt.sign(payload, JWT_SECRET, { expiresIn: TOKEN_EXPIRY });
}

export function verifyToken(token: string): AuthUserPayload | null {
  try {
    return jwt.verify(token, JWT_SECRET) as AuthUserPayload;
  } catch {
    return null;
  }
}

/**
 * Seed initial Workshop Owner account if no users exist in the workshop
 */
export async function seedInitialOwner(prisma: PrismaClient, tenantId: string): Promise<void> {
  try {
    const userCount = await prisma.user.count({ where: { tenantId } });
    if (userCount === 0) {
      const defaultPasswordHash = await hashPassword('password123');
      await prisma.user.create({
        data: {
          name: 'Workshop Owner',
          email: 'owner@autocare.com',
          username: 'owner',
          phone: '0700000000',
          password: defaultPasswordHash,
          role: 'OWNER',
          specialization: 'Workshop Director & General Management',
          commissionRate: 0,
          isActive: true,
          tenantId,
        },
      });
      console.log('✔ Initial Workshop Owner account created (email: owner@autocare.com / username: owner, pass: password123)');
    }
  } catch (err) {
    console.error('Failed to check or seed initial owner:', err);
  }
}

/**
 * Express middleware to authenticate JWT tokens and fall back to headers
 */
export function createAuthMiddleware(prisma: PrismaClient) {
  return async (req: Request, res: Response, next: NextFunction) => {
    try {
      const authHeader = req.headers.authorization;
      if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.substring(7).trim();
        const decoded = verifyToken(token);
        if (decoded) {
          // Verify user still active in database
          const dbUser = await prisma.user.findUnique({
            where: { id: decoded.id },
            select: { id: true, email: true, username: true, name: true, phone: true, role: true, tenantId: true, isActive: true },
          });
          if (dbUser && dbUser.isActive) {
            req.user = {
              id: dbUser.id,
              email: dbUser.email,
              username: dbUser.username,
              name: dbUser.name,
              phone: dbUser.phone,
              role: dbUser.role,
              tenantId: dbUser.tenantId,
            };
            return next();
          }
        }
      }

      // Fallback for transitional legacy headers (or if x-user-role is provided)
      const roleHeader = req.header('x-user-role');
      const nameHeader = req.header('x-user-name');
      if (roleHeader) {
        req.user = {
          id: 'system-actor',
          email: `${roleHeader.toLowerCase()}@autocare.com`,
          username: nameHeader || roleHeader.toLowerCase(),
          name: nameHeader || roleHeader,
          role: roleHeader as Role,
          tenantId: 'default',
        };
        return next();
      }

      next();
    } catch (e) {
      next();
    }
  };
}

/**
 * Helper to enforce role permission
 */
export function requireRoles(...allowedRoles: Role[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) {
      return res.status(401).json({ error: 'Authentication required. Please login.' });
    }
    if (req.user.role === 'SUPER_ADMIN' || req.user.role === 'OWNER') {
      return next(); // Owner and Super Admin have unrestricted master privileges
    }
    if (!allowedRoles.includes(req.user.role)) {
      return res.status(403).json({ error: `Access denied. Role ${req.user.role} is not authorized for this action.` });
    }
    next();
  };
}
