import "@rainbow-me/rainbowkit/styles.css";
import { BugAntIcon } from "@heroicons/react/24/outline";
import { HeaderMenuLink } from "~~/components/Header";
import { ScaffoldEthAppWithProviders } from "~~/components/ScaffoldEthAppWithProviders";
import "~~/styles/globals.css";
import { getMetadata } from "~~/utils/scaffold-eth/getMetadata";

export const metadata = getMetadata({ title: "Scaffold-ETH 2 App", description: "Built with 🏗 Scaffold-ETH 2" });

export const headerMenuLinks: HeaderMenuLink[] = [
  {
    label: "Home",
    href: "/",
  },

  {
    label: "Debug Contracts",
    href: "/debug",
    icon: <BugAntIcon className="h-4 w-4" />,
  },
];

const ScaffoldEthApp = ({ children }: { children: React.ReactNode }) => {
  return <ScaffoldEthAppWithProviders headerMenuLinks={headerMenuLinks}>{children}</ScaffoldEthAppWithProviders>;
};

export default ScaffoldEthApp;
