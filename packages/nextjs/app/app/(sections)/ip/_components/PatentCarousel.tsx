"use client";

import React, { useCallback, useEffect, useState } from "react";
import PatentCard from "./PatentCard";
import useEmblaCarousel from "embla-carousel-react";
import { Patent } from "~~/app/app/_components/AddIpForm";

function chunkArray<T>(arr: T[], size: number): T[][] {
  return Array.from({ length: Math.ceil(arr.length / size) }, (_, i) => arr.slice(i * size, i * size + size));
}

const PATENTS_PER_ROW = 2;
const ROWS_PER_PAGE = 2;
const PATENTS_PER_PAGE = PATENTS_PER_ROW * ROWS_PER_PAGE;

const PatentCarousel = ({ patents }: { patents: Patent[] }) => {
  const [emblaRef, emblaApi] = useEmblaCarousel({ loop: false });
  const [selectedIndex, setSelectedIndex] = useState(0);

  const pages = chunkArray(patents, PATENTS_PER_PAGE);

  useEffect(() => {
    if (!emblaApi) return;
    const onSelect = () => setSelectedIndex(emblaApi.selectedScrollSnap());
    emblaApi.on("select", onSelect);
    onSelect();
    return () => {
      emblaApi.off("select", onSelect);
    };
  }, [emblaApi]);

  const scrollTo = useCallback((idx: number) => emblaApi && emblaApi.scrollTo(idx), [emblaApi]);

  return (
    <div className="relative w-full">
      <div className="embla" ref={emblaRef}>
        <div className="embla__container flex">
          {pages.map((page, pageIdx) => (
            <div className="embla__slide flex-[0_0_100%] px-2" key={pageIdx}>
              <div className="grid grid-cols-2 grid-rows-2 gap-4 h-full">
                {page.map((patent, idx) => (
                  <PatentCard patent={patent} key={patent.name + idx} />
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
      <div className="flex justify-center mt-4 gap-2">
        {pages.map((_, idx) => (
          <button
            key={idx}
            className={`w-3 h-3 rounded-full transition-colors ${idx === selectedIndex ? "bg-primary" : "bg-gray-300"}`}
            onClick={() => scrollTo(idx)}
            aria-label={`Go to page ${idx + 1}`}
          />
        ))}
      </div>
    </div>
  );
};

export default PatentCarousel;
