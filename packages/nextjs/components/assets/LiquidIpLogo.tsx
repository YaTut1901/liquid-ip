import Image from "next/image";

const Logo = ({ width, height, style }: { width: number; height: number; style?: React.CSSProperties }) => {
  return (
    <div className="flex relative" style={{ width, height, ...style }}>
      <Image alt="SE2 logo" className="rounded-lg" fill src="/app/logo.svg" />
    </div>
  );
};

export default Logo;
