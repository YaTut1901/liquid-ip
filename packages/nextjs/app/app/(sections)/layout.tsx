import "@rainbow-me/rainbowkit/styles.css";
import { AuthGuard } from "~~/components/AuthGuard";
import { HeaderMenuLink } from "~~/components/Header";
import { ScaffoldEthAppWithProviders } from "~~/components/ScaffoldEthAppWithProviders";
import PopUp from "~~/components/popup";
import { PopUpProvider } from "~~/components/popup/PopUpContext";
import "~~/styles/globals.css";
import { getMetadata } from "~~/utils/scaffold-eth/getMetadata";

export const metadata = getMetadata({ title: "Scaffold-ETH 2 App", description: "Built with 🏗 Scaffold-ETH 2" });

const headerMenuLinks: HeaderMenuLink[] = [];

const ScaffoldEthApp = ({ children }: { children: React.ReactNode }) => {
  return (
    <ScaffoldEthAppWithProviders
      headerMenuLinks={headerMenuLinks}
      footer={false}
      faucet={false}
      reconnectOnMount={true}
    >
      <AuthGuard>
        <PopUpProvider>
          {children}
          <PopUp />
        </PopUpProvider>
      </AuthGuard>
    </ScaffoldEthAppWithProviders>
  );
};

export default ScaffoldEthApp;
