import { useState } from "react";
import { useRouter } from "next/navigation";
import { usePopUp } from "~~/components/popup/PopUpContext";
import deployedContracts from "~~/contracts/deployedContracts";
import { StorageAdapter } from "~~/services/adapter/Adapter";
import PinataJsonAdapter from "~~/services/adapter/PinataJsonAdapter";

export function useAddIpFormSubmit() {
  const router = useRouter();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { closePopUp } = usePopUp();
  const adapter: StorageAdapter<JSON, string> = new PinataJsonAdapter();

  const uploadIpJsonToStorage: (data: FormData) => Promise<string | undefined> = async (data: FormData) => {
    return adapter
      .write(JSON.parse(JSON.stringify(Object.fromEntries(data))))
      .then(cid => cid)
      .catch(error => {
        setError(error as string);
        return undefined;
      });
  };

  const mintIpNft = async (ipfsUrl: string) => {
    console.log(deployedContracts, ipfsUrl);
  };

  const handleSubmit = async (data: FormData) => {
    setIsLoading(true);
    setError(null);
    uploadIpJsonToStorage(data).then(ipfsUrl => {
      if (ipfsUrl) {
        mintIpNft(ipfsUrl).then(() => {
          setIsLoading(false);
          closePopUp();
          router.push("/app/ip");
        });
      }
    });
  };

  return { handleSubmit, isLoading, error };
}
