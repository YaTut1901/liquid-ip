"use client";

import { useState } from "react";
import LoginButton from "../../_components/Button";
import { useForm } from "react-hook-form";
import { EyeIcon, EyeSlashIcon } from "@heroicons/react/24/outline";

interface RegisterFormData {
  firstName: string;
  lastName: string;
  email: string;
  password: string;
}

interface RegisterFormProps {
  onSubmit: (data: RegisterFormData) => void;
}

export const RegisterForm = ({ onSubmit }: RegisterFormProps) => {
  const [showPassword, setShowPassword] = useState(false);
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<RegisterFormData>();

  const handleFormSubmit = (data: RegisterFormData) => {
    onSubmit(data);
  };

  return (
    <form onSubmit={handleSubmit(handleFormSubmit)} className="w-full max-w-md space-y-6">
      <div className="grid grid-cols-2 gap-4">
        <div className="relative">
          <input
            {...register("firstName", { required: "First name is required" })}
            type="text"
            placeholder="First Name"
            className="w-full px-4 py-2 bg-transparent outline-none"
          />
          <div className="flex flex-col gap-1">
            <div className="w-full h-[1px] border-b-2 border-black"></div>
            <div className="w-full h-[1px] border-b-2 border-black"></div>
          </div>
          {errors.firstName && <span className="text-red-500 text-sm mt-1">{errors.firstName.message}</span>}
        </div>
        <div className="relative">
          <input
            {...register("lastName", { required: "Last name is required" })}
            type="text"
            placeholder="Last Name"
            className="w-full px-4 py-2 bg-transparent outline-none"
          />
          <div className="flex flex-col gap-1">
            <div className="w-full h-[1px] border-b-2 border-black"></div>
            <div className="w-full h-[1px] border-b-2 border-black"></div>
          </div>
          {errors.lastName && <span className="text-red-500 text-sm mt-1">{errors.lastName.message}</span>}
        </div>
      </div>

      <div className="relative">
        <input
          {...register("email", {
            required: "Email is required",
            pattern: {
              value: /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i,
              message: "Invalid email address",
            },
          })}
          type="email"
          placeholder="Email Address"
          className="w-full px-4 py-2 bg-transparent outline-none"
        />
        <div className="flex flex-col gap-1">
          <div className="w-full h-[1px] border-b-2 border-black"></div>
          <div className="w-full h-[1px] border-b-2 border-black"></div>
        </div>
        {errors.email && <span className="text-red-500 text-sm mt-1">{errors.email.message}</span>}
      </div>

      <div className="relative">
        <div className="flex items-center">
          <input
            {...register("password", {
              required: "Password is required",
              minLength: {
                value: 8,
                message: "Password must be at least 8 characters",
              },
            })}
            type={showPassword ? "text" : "password"}
            placeholder="Password"
            className="w-full px-4 py-2 bg-transparent outline-none"
          />
          <button
            type="button"
            onClick={() => setShowPassword(!showPassword)}
            className="absolute right-0 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-700 p-1"
          >
            {showPassword ? <EyeSlashIcon className="w-5 h-5" /> : <EyeIcon className="w-5 h-5" />}
          </button>
        </div>
        <div className="flex flex-col gap-1">
          <div className="w-full h-[1px] border-b-2 border-black"></div>
          <div className="w-full h-[1px] border-b-2 border-black"></div>
        </div>
        {errors.password && <span className="text-red-500 text-sm mt-1">{errors.password.message}</span>}
      </div>

      <LoginButton text="Register" />

      <p className="text-sm text-gray-600 mt-4">
        The &quot;###&quot; terms and conditions apply.
        <br />
        Information on the processing of your data can be
        <br />
        found in our data protection declaration.
      </p>
    </form>
  );
};
