"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { useAccount } from "wagmi";

export const AuthGuard = ({ children }: { children: React.ReactNode }) => {
  const { isConnected } = useAccount();
  const router = useRouter();
  const pathname = usePathname();

  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setTimeout(() => {
      setMounted(true);
    }, 2000);
  }, []);

  useEffect(() => {
    if (mounted && !isConnected) {
      router.push(`/app/login?from=${pathname}`);
    }
  }, [isConnected, pathname, router, mounted]);

  return <>{children}</>;
};
