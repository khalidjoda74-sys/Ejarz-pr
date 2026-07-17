import { useEffect, useState } from 'react';

export function useResponsive() {
  const [width, setWidth] = useState(() => window.innerWidth);
  useEffect(() => {
    const onResize = () => setWidth(window.innerWidth);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);
  return {
    width,
    isMobile: width < 760,
    isTablet: width >= 760 && width < 1180,
    isDesktop: width >= 1180,
  };
}
