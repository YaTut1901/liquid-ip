import "@rainbow-me/rainbowkit/styles.css";
import { ThemeProvider } from "~~/components/ThemeProvider";
import PopUp from "~~/components/popup";
import { PopUpProvider } from "~~/components/popup/PopUpContext";
import "~~/styles/globals.css";

const ScaffoldEthApp = ({ children }: { children: React.ReactNode }) => {
  return (
    <html suppressHydrationWarning>
      <body>
        <ThemeProvider enableSystem>
          <PopUpProvider>
            {children}
            <PopUp />
          </PopUpProvider>
        </ThemeProvider>
      </body>
    </html>
  );
};

export default ScaffoldEthApp;
