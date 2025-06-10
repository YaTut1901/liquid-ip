"use client";

import { ReactNode } from "react";

interface LoginButtonProps {
  text: string;
  icon?: ReactNode;
  onClick?: () => void | Promise<void>;
  styles?: React.CSSProperties;
  className?: string;
  isLoading?: boolean;
  disabled?: boolean;
}

const LoginButton = ({
  text,
  icon,
  onClick,
  styles = {},
  className = "",
  isLoading = false,
  disabled = false,
}: LoginButtonProps) => {
  return (
    <button
      onClick={onClick}
      style={styles}
      disabled={disabled || isLoading}
      className={
        className
          ? className
          : `
        btn btn-primary w-full h-14 text-lg font-medium flex items-center justify-center gap-2 transition-all duration-200 hover:scale-[1.02] active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed`
      }
    >
      {isLoading ? (
        <span className="loading loading-spinner loading-md" />
      ) : (
        <>
          {icon && <span className="w-8 h-8 flex items-center justify-center">{icon}</span>}
          <span>{text}</span>
        </>
      )}
    </button>
  );
};

export default LoginButton;
