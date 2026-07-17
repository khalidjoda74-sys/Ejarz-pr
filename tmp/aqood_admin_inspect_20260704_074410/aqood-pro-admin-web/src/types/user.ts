export type UserStatus = 'active' | 'blocked' | 'suspended';

export interface AppUser {
  uid: string;
  id?: string;
  displayName?: string;
  name?: string;
  phone?: string;
  email?: string;
  status?: UserStatus;
  blocked?: boolean;
  blockedAt?: unknown;
  blockedBy?: string;
  blockReason?: string;
  createdAt?: unknown;
  updatedAt?: unknown;
  lastLoginAt?: unknown;
  [key: string]: unknown;
}

export interface FcmToken {
  id: string;
  token?: string;
  active?: boolean;
  platform?: string;
  createdAt?: unknown;
  updatedAt?: unknown;
  lastSeenAt?: unknown;
}
