import React from "react";
import Image from "next/image";
import { Patent } from "~~/app/app/_components/AddIpForm";

const PatentCard = ({ patent }: { patent: Patent }) => {
  return (
    <div className="flex bg-white rounded-3xl shadow-lg flex items-center justify-between p-3">
      <div className="flex border-4 border-black rounded-tl-[20px] rounded-tr-[20px] rounded-br-[100px] flex flex-col justify-center">
        <div className="flex flex-col items-left p-2">
          <div className="flex flex-col">
            <span className="text-black text-xl font-bold leading-tight">Patent Number</span>
            <span className="text-black text-base font-semibold">{patent.name}</span>
          </div>
          <Image src="/app/patent-icon.png" alt="Patent Icon" width={100} height={100} />
        </div>
      </div>
      <div className="h-full flex flex-col justify-end p-2">
        <Image src="/app/stars.svg" alt="Stars" width={160} height={32} />
      </div>
    </div>
  );
};

export default PatentCard;
