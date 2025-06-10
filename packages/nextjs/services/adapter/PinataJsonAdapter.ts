import { StorageAdapter } from "./Adapter";
import { GetCIDResponse, PinataSDK, UploadResponse } from "pinata";

class PinataJsonAdapter extends StorageAdapter<JSON, string> {
  private readonly pinataClient: PinataSDK;

  constructor() {
    super();

    if (!process.env.NEXT_PUBLIC_PINATA_JWT) {
      throw new Error("NEXT_PUBLIC_PINATA_JWT is not set");
    }
    if (!process.env.NEXT_PUBLIC_PINATA_GATEWAY) {
      throw new Error("NEXT_PUBLIC_PINATA_GATEWAY is not set");
    }

    this.pinataClient = new PinataSDK({
      pinataJwt: process.env.NEXT_PUBLIC_PINATA_JWT,
      pinataGateway: process.env.NEXT_PUBLIC_PINATA_GATEWAY,
    });
  }

  async read(id: string): Promise<JSON> {
    try {
      const response: GetCIDResponse = await this.pinataClient.gateways.public.get(id);
      console.log("Pinata JSON read response: ", response);
      return response.data as JSON;
    } catch (error) {
      console.error("Pinata JSON read error: ", error);
      throw new Error(`Failed to upload to ipfs: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  async write(data: JSON): Promise<string> {
    return new Promise((resolve, reject) => {
      this.pinataClient.upload.public
        .json(data)
        .name(`ip-form-${Date.now()}.json`)
        .then((response: UploadResponse) => {
          console.log("Pinata JSON upload response: ", response);
          resolve(response.cid);
        })
        .catch((error: unknown) => {
          console.error("Pinata JSON write error: ", error);
          reject(new Error(`Failed to upload to ipfs: ${error instanceof Error ? error.message : String(error)}`));
        });
    });
  }
}

export default PinataJsonAdapter;
