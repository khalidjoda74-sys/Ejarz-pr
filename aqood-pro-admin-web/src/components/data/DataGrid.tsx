import { ColumnDef, flexRender, getCoreRowModel, getSortedRowModel, SortingState, useReactTable } from '@tanstack/react-table';
import { useMemo, useState } from 'react';
import { EmptyState } from '@/components/feedback/EmptyState';

export function DataGrid<T extends { id?: string }>({
  data,
  columns,
  mobileTitle,
  mobileSubtitle,
  mobileMeta,
  mobileActions,
}: {
  data: T[];
  columns: ColumnDef<T, unknown>[];
  mobileTitle: (row: T) => string;
  mobileSubtitle?: (row: T) => string;
  mobileMeta?: (row: T) => React.ReactNode;
  mobileActions?: (row: T) => React.ReactNode;
}) {
  const [sorting, setSorting] = useState<SortingState>([]);
  const table = useReactTable({
    data,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  });
  const rows = useMemo(() => table.getRowModel().rows, [table, data, sorting]);
  if (!data.length) return <EmptyState />;
  return <div className="table-shell card-solid">
    <div className="desktop-table" style={{ overflowX: 'auto' }}>
      <table className="data-table">
        <thead>
          {table.getHeaderGroups().map((headerGroup) => <tr key={headerGroup.id}>
            {headerGroup.headers.map((header) => <th key={header.id} onClick={header.column.getToggleSortingHandler()} style={{ cursor: header.column.getCanSort() ? 'pointer' : 'default' }}>
              {header.isPlaceholder ? null : flexRender(header.column.columnDef.header, header.getContext())}
              {{ asc: ' ↑', desc: ' ↓' }[header.column.getIsSorted() as string] ?? null}
            </th>)}
          </tr>)}
        </thead>
        <tbody>
          {rows.map((row) => <tr key={row.id}>
            {row.getVisibleCells().map((cell) => <td key={cell.id}>{flexRender(cell.column.columnDef.cell, cell.getContext())}</td>)}
          </tr>)}
        </tbody>
      </table>
    </div>
    <div className="mobile-cards" style={{ padding: 10 }}>
      {data.map((row, index) => <div className="card-solid" style={{ padding: 14 }} key={row.id ?? index}>
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10, alignItems: 'flex-start' }}>
          <div>
            <strong style={{ fontSize: '1rem' }}>{mobileTitle(row)}</strong>
            {mobileSubtitle && <p className="page-subtitle" style={{ margin: '4px 0 0' }}>{mobileSubtitle(row)}</p>}
          </div>
          {mobileActions?.(row)}
        </div>
        {mobileMeta && <div style={{ marginTop: 12 }}>{mobileMeta(row)}</div>}
      </div>)}
    </div>
  </div>;
}
