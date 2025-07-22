"use client";

import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Logo from "../../../components/assets/LiquidIpLogo";
import LoginButton from "../_components/Button";
import { RegisterForm } from "./_components/RegisterForm";
import { type NextPage } from "next";
import { RainbowKitCustomConnectButton } from "~~/components/scaffold-eth/RainbowKitCustomConnectButton";

const handleComingSoon = () => {
  alert("Coming Soon!");
};

const LoginPage: NextPage = () => {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const router = useRouter();
  const searchParams = useSearchParams();

  useEffect(() => {
    if (isLoggedIn) {
      router.push(searchParams.get("from") || "/app");
    }
  }, [isLoggedIn, router]);

  return (
    <div className="flex h-screen flex-col bg-base-100 p-14">
      <div className="grid grid-cols-[4fr_1fr_4fr] grid-rows-[1fr_7fr] gap-4 w-full h-full">
        <div className="flex h-full">
          <Logo width={100} height={100} />
        </div>
        <div className="text-4xl font-bold flex items-center justify-center h-full">Register</div>
        <div className="flex items-center justify-center h-full"></div>
        <div className="flex p-16 h-full">
          <RegisterForm onSubmit={() => handleComingSoon()} />
        </div>
        <div className="flex justify-center h-full">
          <div className="w-1 h-[550px] bg-black"></div>
        </div>
        <div className="flex flex-col gap-4 p-16 h-full">
          <LoginButton
            text="Login with Google"
            icon={<img src="/app/google-icon.svg" alt="Google" />}
            onClick={handleComingSoon}
          />
          <LoginButton
            text="Login with Apple"
            icon={<img src="/app/apple-icon.svg" alt="Apple" />}
            onClick={handleComingSoon}
          />
          <LoginButton
            text="Login with Facebook"
            icon={<img src="/app/facebook-icon.svg" alt="Facebook" />}
            onClick={handleComingSoon}
          />
          <RainbowKitCustomConnectButton
            text="Connect Web3 Wallet"
            icon={<img src="/app/web3-wallet.svg" alt="Web3 wallet" />}
            dropdown={false}
            setIsLoggedIn={setIsLoggedIn}
          />
        </div>
      </div>
    </div>
  );
};

export default LoginPage;
