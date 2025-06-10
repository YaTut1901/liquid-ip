"use client";

import AddIpForm from "../_components/AddIpForm";
import Button from "../_components/Button";
import { usePopUp } from "~~/components/popup/PopUpContext";

const handleComingSoon = () => {
  alert("Coming Soon!");
};

export default function App() {
  const { openPopUp } = usePopUp();

  return (
    <div className="flex w-full h-full flex-1 flex-col gap-24 items-center justify-center">
      <div className="flex justify-center gap-[275px]">
        <Button text="Take License" onClick={handleComingSoon} styles={{ width: "495px", height: "80px" }} />
        <Button text="Market License" onClick={handleComingSoon} styles={{ width: "495px", height: "80px" }} />
      </div>
      <Button text="Add IP" onClick={() => openPopUp(<AddIpForm />)} styles={{ width: "495px", height: "80px" }} />
    </div>
  );
}
