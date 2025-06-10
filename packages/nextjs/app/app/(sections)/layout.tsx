import "@rainbow-me/rainbowkit/styles.css";
import { HeaderMenuLink } from "~~/components/Header";
import { ScaffoldEthAppWithProviders } from "~~/components/ScaffoldEthAppWithProviders";
import "~~/styles/globals.css";
import { getMetadata } from "~~/utils/scaffold-eth/getMetadata";

export const metadata = getMetadata({ title: "Scaffold-ETH 2 App", description: "Built with 🏗 Scaffold-ETH 2" });

const headerMenuLinks: HeaderMenuLink[] = [
  {
    label: "Home",
    href: "/",
  },
];

const ScaffoldEthApp = ({ children }: { children: React.ReactNode }) => {
  return (
    <ScaffoldEthAppWithProviders headerMenuLinks={headerMenuLinks} footer={false} faucet={false}>
      {children}
    </ScaffoldEthAppWithProviders>
  );
};

export default ScaffoldEthApp;
