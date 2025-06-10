"use client";

import { useEffect, useState } from "react";
import { HeaderMenuLink } from "./Header";
import { RainbowKitProvider, darkTheme, lightTheme } from "@rainbow-me/rainbowkit";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { AppProgressBar as ProgressBar } from "next-nprogress-bar";
import { useTheme } from "next-themes";
import { Toaster } from "react-hot-toast";
import { WagmiProvider } from "wagmi";
import { Footer } from "~~/components/Footer";
import { Header } from "~~/components/Header";
import { BlockieAvatar } from "~~/components/scaffold-eth";
import { useInitializeNativeCurrencyPrice } from "~~/hooks/scaffold-eth";
import { wagmiConfig } from "~~/services/web3/wagmiConfig";

const ScaffoldEthApp = ({
  children,
  headerMenuLinks,
  header,
  footer,
  faucet,
}: {
  children: React.ReactNode;
  headerMenuLinks?: HeaderMenuLink[];
  header?: boolean;
  footer?: boolean;
  faucet?: boolean;
}) => {
  useInitializeNativeCurrencyPrice();

  return (
    <>
      <div className={`flex flex-col min-h-screen `}>
        {header && <Header menuLinks={headerMenuLinks} faucet={faucet} />}
        <main className="relative flex flex-col flex-1">{children}</main>
        {footer && <Footer />}
      </div>
      <Toaster />
    </>
  );
};

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
    },
  },
});

export const ScaffoldEthAppWithProviders = ({
  children,
  headerMenuLinks,
  header = true,
  footer = true,
  faucet = true,
  reconnectOnMount = false,
}: {
  children: React.ReactNode;
  headerMenuLinks?: HeaderMenuLink[];
  header?: boolean;
  footer?: boolean;
  faucet?: boolean;
  reconnectOnMount?: boolean;
}) => {
  const { resolvedTheme } = useTheme();
  const isDarkMode = resolvedTheme === "dark";
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  return (
    <WagmiProvider config={wagmiConfig} reconnectOnMount={reconnectOnMount}>
      <QueryClientProvider client={queryClient}>
        <ProgressBar height="3px" color="#2299dd" />
        <RainbowKitProvider
          avatar={BlockieAvatar}
          theme={mounted ? (isDarkMode ? darkTheme() : lightTheme()) : lightTheme()}
        >
          <ScaffoldEthApp headerMenuLinks={headerMenuLinks} header={header} footer={footer} faucet={faucet}>
            {children}
          </ScaffoldEthApp>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
};
