"use client";

import React, { ReactNode, createContext, useContext, useEffect, useState } from "react";

interface PopUpContextType {
  isPoppedUp: boolean;
  children: ReactNode;
  openPopUp: (children: ReactNode) => void;
  closePopUp: () => void;
}

const PopUpContext = createContext<PopUpContextType | null>(null);

export const PopUpProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [isPoppedUp, setIsPoppedUp] = useState(false);
  const [popUpChildren, setPopUpChildren] = useState<ReactNode>(null);

  const openPopUp = (children: ReactNode) => {
    setIsPoppedUp(true);
    setPopUpChildren(children);
  };

  useEffect(() => {
    if (isPoppedUp) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }

    return () => {
      document.body.style.overflow = "";
    };
  }, [isPoppedUp]);

  const closePopUp = () => setIsPoppedUp(false);

  return (
    <PopUpContext.Provider value={{ isPoppedUp, children: popUpChildren, openPopUp, closePopUp }}>
      {children}
    </PopUpContext.Provider>
  );
};

export const usePopUp = (): PopUpContextType => {
  const context = useContext(PopUpContext);
  if (!context) {
    throw new Error("usePopUp must be used within a PopUpProvider");
  }
  return context;
};
