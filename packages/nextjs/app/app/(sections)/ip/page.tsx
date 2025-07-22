"use client";

import PatentCarousel from "./_components/PatentCarousel";

export default function IP() {
  const patents = [
    {
      name: "US9876543B2",
      url: "asdasdasd",
    },
    {
      name: "EP1234567B1",
      url: "asdasdasd",
    },
    {
      name: "JP1234567B1",
      url: "asdasdasd",
    },
    {
      name: "US9876543B2",
      url: "asdasdasd",
    },
    {
      name: "EP1234567B1",
      url: "asdasdasd",
    },
    {
      name: "JP1234567B1",
      url: "asdasdasd",
    },
    {
      name: "US9876543B2",
      url: "asdasdasd",
    },
    {
      name: "EP1234567B1",
      url: "asdasdasd",
    },
    {
      name: "JP1234567B1",
      url: "asdasdasd",
    },
    {
      name: "US9876543B2",
      url: "asdasdasd",
    },
    {
      name: "EP1234567B1",
      url: "asdasdasd",
    },
    {
      name: "JP1234567B1",
      url: "asdasdasd",
    },
  ];

  return (
    <main className="flex flex-1 items-center justify-center p-6">
      <PatentCarousel patents={patents} />
    </main>
  );
}
