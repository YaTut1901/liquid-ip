"use client";

import React, { useState } from "react";
import { useAddIpFormSubmit } from "~~/hooks/app";

export interface Patent {
  name: string;
  url: string;
}

const AddIpForm: React.FC = () => {
  const { handleSubmit, isLoading } = useAddIpFormSubmit();

  const [formData, setFormData] = useState<Patent>({
    name: "",
    url: "",
  } as Patent);

  const handleSubmitForm = (e: React.FormEvent) => {
    e.preventDefault();
    handleSubmit(new FormData(e.target as HTMLFormElement));
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value,
    }));
  };

  return (
    <form onSubmit={handleSubmitForm} className="w-[495px] bg-base-200 p-8 rounded-xl shadow-lg">
      <h2 className="text-2xl font-bold mb-6">Add New IP</h2>

      <div className="space-y-4">
        <div className="form-control w-full flex flex-col gap-1">
          <label className="label">
            <span className="label-text">Name</span>
          </label>
          <input
            type="text"
            name="name"
            value={formData.name}
            onChange={handleChange}
            placeholder="Enter IP name"
            className="input input-bordered w-full"
            required
          />
        </div>

        <div className="form-control w-full flex flex-col gap-1">
          <label className="label">
            <span className="label-text">URL</span>
          </label>
          <input
            type="url"
            name="url"
            value={formData.url}
            onChange={handleChange}
            placeholder="https://example.com"
            className="input input-bordered w-full"
            required
          />
        </div>
      </div>

      <div className="mt-8">
        <button type="submit" disabled={isLoading} className="btn btn-primary w-full h-14 text-lg font-medium relative">
          {isLoading ? (
            <span className="flex items-center gap-2">
              Loading
              <span className="loading loading-spinner loading-sm"></span>
            </span>
          ) : (
            "Submit"
          )}
        </button>
      </div>
    </form>
  );
};

export default AddIpForm;
