export interface Property {
  id: string;
  uid?: string;
  userId?: string;
  ownerName?: string;
  title?: string;
  city?: string;
  district?: string;
  type?: string;
  usage?: string;
  status?: string;
  floors?: number;
  unitsPerFloor?: number;
  totalUnits?: number;
  sourceContractId?: string;
  units?: PropertyUnit[];
  createdAt?: unknown;
  updatedAt?: unknown;
  [key: string]: unknown;
}

export interface PropertyUnit {
  number?: string;
  name?: string;
  type?: string;
  floor?: string;
  area?: string;
  status?: string;
  roomsCount?: number;
  bathroomsCount?: number;
  hallsCount?: number;
  maidRoom?: boolean;
  kitchen?: boolean;
  storage?: boolean;
  majlis?: boolean;
  furnishingStatus?: string;
  privateParking?: boolean;
  electricityMeter?: string;
  waterMeter?: string;
  gasMeter?: string;
  acWindow?: boolean;
  acSplit?: boolean;
  acCentral?: boolean;
  notes?: string;
  [key: string]: unknown;
}
