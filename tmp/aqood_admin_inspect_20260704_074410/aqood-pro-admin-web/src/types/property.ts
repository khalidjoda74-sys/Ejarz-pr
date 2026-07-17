export interface Property {
  id: string;
  userId?: string;
  ownerName?: string;
  title?: string;
  city?: string;
  district?: string;
  type?: string;
  usage?: string;
  status?: string;
  units?: Record<string, unknown>[];
  createdAt?: unknown;
  updatedAt?: unknown;
  [key: string]: unknown;
}
