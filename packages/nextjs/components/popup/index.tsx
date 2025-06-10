"use client";

import React from "react";
import { usePopUp } from "./PopUpContext";

const PopUp: React.FC = () => {
  const { isPoppedUp, children, closePopUp } = usePopUp();

  if (!isPoppedUp) {
    return null;
  }

  return (
    <div
      className="fixed top-0 left-0 w-full h-full flex z-50 animate-fadeIn bg-black/50 justify-center items-center"
      onClick={closePopUp}
    >
      <div onClick={e => e.stopPropagation()}>{children}</div>
    </div>
  );
};

export default PopUp;
