// import { useAccount } from "wagmi";
// import { useScaffoldEventHistory, useScaffoldReadContract } from "~~/hooks/scaffold-eth";
// import { useEffect, useState } from "react";
// import { Patent } from "~~/app/app/_components/AddIpForm";
// import PinataJsonAdapter from "~~/services/adapter/PinataJsonAdapter";
// import { zeroAddress } from "viem";

// export function useFetchPatents() {
//   const { address } = useAccount();
//   const [patents, setPatents] = useState<Patent[]>([]);
//   const pinata = new PinataJsonAdapter();

//   const { data: events } = useScaffoldEventHistory({
//     contractName: "PatentERC721",
//     eventName: "Transfer",
//     filters: { from: zeroAddress, to: address },
//     fromBlock: 0n,
//     watch: false,
//   });

//   useEffect(() => {
//     const fetchPatents = async () => {
//       if (!events) return;
//       const tokenIds = events
//         .map(e => e.args?.tokenId)
//         .filter(tokenId => tokenId !== undefined);

//       const uris = await Promise.all(
//         tokenIds.map(tokenId =>
//           useScaffoldReadContract({
//             contractName: "PatentERC721",
//             functionName: "tokenURI",
//             args: [tokenId],
//           }).data
//         )
//       );

//       const cids = uris.map(uri => {
//         if (!uri) return null;
//         if (uri.startsWith("ipfs://")) return uri.replace("ipfs://", "");
//         try {
//           const url = new URL(uri);
//           return url.pathname.replace(/^\//, "");
//         } catch {
//           return uri;
//         }
//       });

//       const patentData = await Promise.all(
//         cids.map(async cid => {
//           if (!cid) return null;
//           try {
//             return await pinata.read(cid);
//           } catch {
//             return null;
//           }
//         })
//       );

//       setPatents(patentData.filter(Boolean));
//     };

//     fetchPatents();
//   }, [events, address]);

//   return patents;
// }
