import { HTMLAttributes } from 'react';
import { clsx } from 'clsx';

export function Card({ className, goldLine, ...props }: HTMLAttributes<HTMLDivElement> & { goldLine?: boolean }) {
  return <div className={clsx('card', goldLine && 'gold-line', className)} {...props} />;
}

export function SolidCard({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={clsx('card-solid', className)} {...props} />;
}
