export function getErrorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string') return error;
  return 'حدث خطأ غير متوقع';
}

export class PermissionError extends Error {
  constructor(message = 'لا تملك صلاحية تنفيذ هذا الإجراء') {
    super(message);
    this.name = 'PermissionError';
  }
}
