import { GenericContractsDeclaration } from "~~/utils/scaffold-eth/contract";

/**
 * @example
 * const externalContracts = {
 *   1: {
 *     DAI: {
 *       address: "0x...",
 *       abi: [...],
 *     },
 *   },
 * } as const;
 */
const externalContracts = {
  31337: {
    IPoolManager: {
      address: "0x000000000004444c5dc75cB358380D2e3dE08A90",
      abi: [
        {
          type: "function",
          name: "allowance",
          inputs: [
            {
              name: "owner",
              type: "address",
              internalType: "address",
            },
            {
              name: "spender",
              type: "address",
              internalType: "address",
            },
            {
              name: "id",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "approve",
          inputs: [
            {
              name: "spender",
              type: "address",
              internalType: "address",
            },
            {
              name: "id",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "balanceOf",
          inputs: [
            {
              name: "owner",
              type: "address",
              internalType: "address",
            },
            {
              name: "id",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "burn",
          inputs: [
            {
              name: "from",
              type: "address",
              internalType: "address",
            },
            {
              name: "id",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "clear",
          inputs: [
            {
              name: "currency",
              type: "address",
              internalType: "Currency",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "collectProtocolFees",
          inputs: [
            {
              name: "recipient",
              type: "address",
              internalType: "address",
            },
            {
              name: "currency",
              type: "address",
              internalType: "Currency",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "amountCollected",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "donate",
          inputs: [
            {
              name: "key",
              type: "tuple",
              internalType: "struct PoolKey",
              components: [
                {
                  name: "currency0",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "currency1",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "fee",
                  type: "uint24",
                  internalType: "uint24",
                },
                {
                  name: "tickSpacing",
                  type: "int24",
                  internalType: "int24",
                },
                {
                  name: "hooks",
                  type: "address",
                  internalType: "contract IHooks",
                },
              ],
            },
            {
              name: "amount0",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "amount1",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "hookData",
              type: "bytes",
              internalType: "bytes",
            },
          ],
          outputs: [
            {
              name: "",
              type: "int256",
              internalType: "BalanceDelta",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "extsload",
          inputs: [
            {
              name: "slot",
              type: "bytes32",
              internalType: "bytes32",
            },
          ],
          outputs: [
            {
              name: "value",
              type: "bytes32",
              internalType: "bytes32",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "extsload",
          inputs: [
            {
              name: "startSlot",
              type: "bytes32",
              internalType: "bytes32",
            },
            {
              name: "nSlots",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "values",
              type: "bytes32[]",
              internalType: "bytes32[]",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "extsload",
          inputs: [
            {
              name: "slots",
              type: "bytes32[]",
              internalType: "bytes32[]",
            },
          ],
          outputs: [
            {
              name: "values",
              type: "bytes32[]",
              internalType: "bytes32[]",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "exttload",
          inputs: [
            {
              name: "slots",
              type: "bytes32[]",
              internalType: "bytes32[]",
            },
          ],
          outputs: [
            {
              name: "values",
              type: "bytes32[]",
              internalType: "bytes32[]",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "exttload",
          inputs: [
            {
              name: "slot",
              type: "bytes32",
              internalType: "bytes32",
            },
          ],
          outputs: [
            {
              name: "value",
              type: "bytes32",
              internalType: "bytes32",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "initialize",
          inputs: [
            {
              name: "key",
              type: "tuple",
              internalType: "struct PoolKey",
              components: [
                {
                  name: "currency0",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "currency1",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "fee",
                  type: "uint24",
                  internalType: "uint24",
                },
                {
                  name: "tickSpacing",
                  type: "int24",
                  internalType: "int24",
                },
                {
                  name: "hooks",
                  type: "address",
                  internalType: "contract IHooks",
                },
              ],
            },
            {
              name: "sqrtPriceX96",
              type: "uint160",
              internalType: "uint160",
            },
          ],
          outputs: [
            {
              name: "tick",
              type: "int24",
              internalType: "int24",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "isOperator",
          inputs: [
            {
              name: "owner",
              type: "address",
              internalType: "address",
            },
            {
              name: "spender",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "approved",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "mint",
          inputs: [
            {
              name: "to",
              type: "address",
              internalType: "address",
            },
            {
              name: "id",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "modifyLiquidity",
          inputs: [
            {
              name: "key",
              type: "tuple",
              internalType: "struct PoolKey",
              components: [
                {
                  name: "currency0",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "currency1",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "fee",
                  type: "uint24",
                  internalType: "uint24",
                },
                {
                  name: "tickSpacing",
                  type: "int24",
                  internalType: "int24",
                },
                {
                  name: "hooks",
                  type: "address",
                  internalType: "contract IHooks",
                },
              ],
            },
            {
              name: "params",
              type: "tuple",
              internalType: "struct ModifyLiquidityParams",
              components: [
                {
                  name: "tickLower",
                  type: "int24",
                  internalType: "int24",
                },
                {
                  name: "tickUpper",
                  type: "int24",
                  internalType: "int24",
                },
                {
                  name: "liquidityDelta",
                  type: "int256",
                  internalType: "int256",
                },
                {
                  name: "salt",
                  type: "bytes32",
                  internalType: "bytes32",
                },
              ],
            },
            {
              name: "hookData",
              type: "bytes",
              internalType: "bytes",
            },
          ],
          outputs: [
            {
              name: "callerDelta",
              type: "int256",
              internalType: "BalanceDelta",
            },
            {
              name: "feesAccrued",
              type: "int256",
              internalType: "BalanceDelta",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "protocolFeeController",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "address",
              internalType: "address",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "protocolFeesAccrued",
          inputs: [
            {
              name: "currency",
              type: "address",
              internalType: "Currency",
            },
          ],
          outputs: [
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "setOperator",
          inputs: [
            {
              name: "operator",
              type: "address",
              internalType: "address",
            },
            {
              name: "approved",
              type: "bool",
              internalType: "bool",
            },
          ],
          outputs: [
            {
              name: "",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "setProtocolFee",
          inputs: [
            {
              name: "key",
              type: "tuple",
              internalType: "struct PoolKey",
              components: [
                {
                  name: "currency0",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "currency1",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "fee",
                  type: "uint24",
                  internalType: "uint24",
                },
                {
                  name: "tickSpacing",
                  type: "int24",
                  internalType: "int24",
                },
                {
                  name: "hooks",
                  type: "address",
                  internalType: "contract IHooks",
                },
              ],
            },
            {
              name: "newProtocolFee",
              type: "uint24",
              internalType: "uint24",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "setProtocolFeeController",
          inputs: [
            {
              name: "controller",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "settle",
          inputs: [],
          outputs: [
            {
              name: "paid",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "payable",
        },
        {
          type: "function",
          name: "settleFor",
          inputs: [
            {
              name: "recipient",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "paid",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "payable",
        },
        {
          type: "function",
          name: "swap",
          inputs: [
            {
              name: "key",
              type: "tuple",
              internalType: "struct PoolKey",
              components: [
                {
                  name: "currency0",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "currency1",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "fee",
                  type: "uint24",
                  internalType: "uint24",
                },
                {
                  name: "tickSpacing",
                  type: "int24",
                  internalType: "int24",
                },
                {
                  name: "hooks",
                  type: "address",
                  internalType: "contract IHooks",
                },
              ],
            },
            {
              name: "params",
              type: "tuple",
              internalType: "struct SwapParams",
              components: [
                {
                  name: "zeroForOne",
                  type: "bool",
                  internalType: "bool",
                },
                {
                  name: "amountSpecified",
                  type: "int256",
                  internalType: "int256",
                },
                {
                  name: "sqrtPriceLimitX96",
                  type: "uint160",
                  internalType: "uint160",
                },
              ],
            },
            {
              name: "hookData",
              type: "bytes",
              internalType: "bytes",
            },
          ],
          outputs: [
            {
              name: "swapDelta",
              type: "int256",
              internalType: "BalanceDelta",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "sync",
          inputs: [
            {
              name: "currency",
              type: "address",
              internalType: "Currency",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "take",
          inputs: [
            {
              name: "currency",
              type: "address",
              internalType: "Currency",
            },
            {
              name: "to",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "transfer",
          inputs: [
            {
              name: "receiver",
              type: "address",
              internalType: "address",
            },
            {
              name: "id",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "transferFrom",
          inputs: [
            {
              name: "sender",
              type: "address",
              internalType: "address",
            },
            {
              name: "receiver",
              type: "address",
              internalType: "address",
            },
            {
              name: "id",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "unlock",
          inputs: [
            {
              name: "data",
              type: "bytes",
              internalType: "bytes",
            },
          ],
          outputs: [
            {
              name: "",
              type: "bytes",
              internalType: "bytes",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "updateDynamicLPFee",
          inputs: [
            {
              name: "key",
              type: "tuple",
              internalType: "struct PoolKey",
              components: [
                {
                  name: "currency0",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "currency1",
                  type: "address",
                  internalType: "Currency",
                },
                {
                  name: "fee",
                  type: "uint24",
                  internalType: "uint24",
                },
                {
                  name: "tickSpacing",
                  type: "int24",
                  internalType: "int24",
                },
                {
                  name: "hooks",
                  type: "address",
                  internalType: "contract IHooks",
                },
              ],
            },
            {
              name: "newDynamicLPFee",
              type: "uint24",
              internalType: "uint24",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "event",
          name: "Approval",
          inputs: [
            {
              name: "owner",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "spender",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "id",
              type: "uint256",
              indexed: true,
              internalType: "uint256",
            },
            {
              name: "amount",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "Donate",
          inputs: [
            {
              name: "id",
              type: "bytes32",
              indexed: true,
              internalType: "PoolId",
            },
            {
              name: "sender",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "amount0",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "amount1",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "Initialize",
          inputs: [
            {
              name: "id",
              type: "bytes32",
              indexed: true,
              internalType: "PoolId",
            },
            {
              name: "currency0",
              type: "address",
              indexed: true,
              internalType: "Currency",
            },
            {
              name: "currency1",
              type: "address",
              indexed: true,
              internalType: "Currency",
            },
            {
              name: "fee",
              type: "uint24",
              indexed: false,
              internalType: "uint24",
            },
            {
              name: "tickSpacing",
              type: "int24",
              indexed: false,
              internalType: "int24",
            },
            {
              name: "hooks",
              type: "address",
              indexed: false,
              internalType: "contract IHooks",
            },
            {
              name: "sqrtPriceX96",
              type: "uint160",
              indexed: false,
              internalType: "uint160",
            },
            {
              name: "tick",
              type: "int24",
              indexed: false,
              internalType: "int24",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "ModifyLiquidity",
          inputs: [
            {
              name: "id",
              type: "bytes32",
              indexed: true,
              internalType: "PoolId",
            },
            {
              name: "sender",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "tickLower",
              type: "int24",
              indexed: false,
              internalType: "int24",
            },
            {
              name: "tickUpper",
              type: "int24",
              indexed: false,
              internalType: "int24",
            },
            {
              name: "liquidityDelta",
              type: "int256",
              indexed: false,
              internalType: "int256",
            },
            {
              name: "salt",
              type: "bytes32",
              indexed: false,
              internalType: "bytes32",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "OperatorSet",
          inputs: [
            {
              name: "owner",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "operator",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "approved",
              type: "bool",
              indexed: false,
              internalType: "bool",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "ProtocolFeeControllerUpdated",
          inputs: [
            {
              name: "protocolFeeController",
              type: "address",
              indexed: true,
              internalType: "address",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "ProtocolFeeUpdated",
          inputs: [
            {
              name: "id",
              type: "bytes32",
              indexed: true,
              internalType: "PoolId",
            },
            {
              name: "protocolFee",
              type: "uint24",
              indexed: false,
              internalType: "uint24",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "Swap",
          inputs: [
            {
              name: "id",
              type: "bytes32",
              indexed: true,
              internalType: "PoolId",
            },
            {
              name: "sender",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "amount0",
              type: "int128",
              indexed: false,
              internalType: "int128",
            },
            {
              name: "amount1",
              type: "int128",
              indexed: false,
              internalType: "int128",
            },
            {
              name: "sqrtPriceX96",
              type: "uint160",
              indexed: false,
              internalType: "uint160",
            },
            {
              name: "liquidity",
              type: "uint128",
              indexed: false,
              internalType: "uint128",
            },
            {
              name: "tick",
              type: "int24",
              indexed: false,
              internalType: "int24",
            },
            {
              name: "fee",
              type: "uint24",
              indexed: false,
              internalType: "uint24",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "Transfer",
          inputs: [
            {
              name: "caller",
              type: "address",
              indexed: false,
              internalType: "address",
            },
            {
              name: "from",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "to",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "id",
              type: "uint256",
              indexed: true,
              internalType: "uint256",
            },
            {
              name: "amount",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
          ],
          anonymous: false,
        },
        {
          type: "error",
          name: "AlreadyUnlocked",
          inputs: [],
        },
        {
          type: "error",
          name: "CurrenciesOutOfOrderOrEqual",
          inputs: [
            {
              name: "currency0",
              type: "address",
              internalType: "address",
            },
            {
              name: "currency1",
              type: "address",
              internalType: "address",
            },
          ],
        },
        {
          type: "error",
          name: "CurrencyNotSettled",
          inputs: [],
        },
        {
          type: "error",
          name: "InvalidCaller",
          inputs: [],
        },
        {
          type: "error",
          name: "ManagerLocked",
          inputs: [],
        },
        {
          type: "error",
          name: "MustClearExactPositiveDelta",
          inputs: [],
        },
        {
          type: "error",
          name: "NonzeroNativeValue",
          inputs: [],
        },
        {
          type: "error",
          name: "PoolNotInitialized",
          inputs: [],
        },
        {
          type: "error",
          name: "ProtocolFeeCurrencySynced",
          inputs: [],
        },
        {
          type: "error",
          name: "ProtocolFeeTooLarge",
          inputs: [
            {
              name: "fee",
              type: "uint24",
              internalType: "uint24",
            },
          ],
        },
        {
          type: "error",
          name: "SwapAmountCannotBeZero",
          inputs: [],
        },
        {
          type: "error",
          name: "TickSpacingTooLarge",
          inputs: [
            {
              name: "tickSpacing",
              type: "int24",
              internalType: "int24",
            },
          ],
        },
        {
          type: "error",
          name: "TickSpacingTooSmall",
          inputs: [
            {
              name: "tickSpacing",
              type: "int24",
              internalType: "int24",
            },
          ],
        },
        {
          type: "error",
          name: "UnauthorizedDynamicLPFeeUpdate",
          inputs: [],
        },
      ],
    },
    IPool: {
      address: "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
      abi: [
        {
          type: "function",
          name: "ADDRESSES_PROVIDER",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "address",
              internalType: "contract IPoolAddressesProvider",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "BRIDGE_PROTOCOL_FEE",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "FLASHLOAN_PREMIUM_TOTAL",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "uint128",
              internalType: "uint128",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "FLASHLOAN_PREMIUM_TO_PROTOCOL",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "uint128",
              internalType: "uint128",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "MAX_NUMBER_RESERVES",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "uint16",
              internalType: "uint16",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "MAX_STABLE_RATE_BORROW_SIZE_PERCENT",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "backUnbacked",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "fee",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "borrow",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "interestRateMode",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "referralCode",
              type: "uint16",
              internalType: "uint16",
            },
            {
              name: "onBehalfOf",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "configureEModeCategory",
          inputs: [
            {
              name: "id",
              type: "uint8",
              internalType: "uint8",
            },
            {
              name: "config",
              type: "tuple",
              internalType: "struct DataTypes.EModeCategory",
              components: [
                {
                  name: "ltv",
                  type: "uint16",
                  internalType: "uint16",
                },
                {
                  name: "liquidationThreshold",
                  type: "uint16",
                  internalType: "uint16",
                },
                {
                  name: "liquidationBonus",
                  type: "uint16",
                  internalType: "uint16",
                },
                {
                  name: "priceSource",
                  type: "address",
                  internalType: "address",
                },
                {
                  name: "label",
                  type: "string",
                  internalType: "string",
                },
              ],
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "deposit",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "onBehalfOf",
              type: "address",
              internalType: "address",
            },
            {
              name: "referralCode",
              type: "uint16",
              internalType: "uint16",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "dropReserve",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "finalizeTransfer",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "from",
              type: "address",
              internalType: "address",
            },
            {
              name: "to",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "balanceFromBefore",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "balanceToBefore",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "flashLoan",
          inputs: [
            {
              name: "receiverAddress",
              type: "address",
              internalType: "address",
            },
            {
              name: "assets",
              type: "address[]",
              internalType: "address[]",
            },
            {
              name: "amounts",
              type: "uint256[]",
              internalType: "uint256[]",
            },
            {
              name: "interestRateModes",
              type: "uint256[]",
              internalType: "uint256[]",
            },
            {
              name: "onBehalfOf",
              type: "address",
              internalType: "address",
            },
            {
              name: "params",
              type: "bytes",
              internalType: "bytes",
            },
            {
              name: "referralCode",
              type: "uint16",
              internalType: "uint16",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "flashLoanSimple",
          inputs: [
            {
              name: "receiverAddress",
              type: "address",
              internalType: "address",
            },
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "params",
              type: "bytes",
              internalType: "bytes",
            },
            {
              name: "referralCode",
              type: "uint16",
              internalType: "uint16",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "getConfiguration",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "tuple",
              internalType: "struct DataTypes.ReserveConfigurationMap",
              components: [
                {
                  name: "data",
                  type: "uint256",
                  internalType: "uint256",
                },
              ],
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getEModeCategoryData",
          inputs: [
            {
              name: "id",
              type: "uint8",
              internalType: "uint8",
            },
          ],
          outputs: [
            {
              name: "",
              type: "tuple",
              internalType: "struct DataTypes.EModeCategory",
              components: [
                {
                  name: "ltv",
                  type: "uint16",
                  internalType: "uint16",
                },
                {
                  name: "liquidationThreshold",
                  type: "uint16",
                  internalType: "uint16",
                },
                {
                  name: "liquidationBonus",
                  type: "uint16",
                  internalType: "uint16",
                },
                {
                  name: "priceSource",
                  type: "address",
                  internalType: "address",
                },
                {
                  name: "label",
                  type: "string",
                  internalType: "string",
                },
              ],
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getReserveAddressById",
          inputs: [
            {
              name: "id",
              type: "uint16",
              internalType: "uint16",
            },
          ],
          outputs: [
            {
              name: "",
              type: "address",
              internalType: "address",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getReserveData",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "tuple",
              internalType: "struct DataTypes.ReserveData",
              components: [
                {
                  name: "configuration",
                  type: "tuple",
                  internalType: "struct DataTypes.ReserveConfigurationMap",
                  components: [
                    {
                      name: "data",
                      type: "uint256",
                      internalType: "uint256",
                    },
                  ],
                },
                {
                  name: "liquidityIndex",
                  type: "uint128",
                  internalType: "uint128",
                },
                {
                  name: "currentLiquidityRate",
                  type: "uint128",
                  internalType: "uint128",
                },
                {
                  name: "variableBorrowIndex",
                  type: "uint128",
                  internalType: "uint128",
                },
                {
                  name: "currentVariableBorrowRate",
                  type: "uint128",
                  internalType: "uint128",
                },
                {
                  name: "currentStableBorrowRate",
                  type: "uint128",
                  internalType: "uint128",
                },
                {
                  name: "lastUpdateTimestamp",
                  type: "uint40",
                  internalType: "uint40",
                },
                {
                  name: "id",
                  type: "uint16",
                  internalType: "uint16",
                },
                {
                  name: "aTokenAddress",
                  type: "address",
                  internalType: "address",
                },
                {
                  name: "stableDebtTokenAddress",
                  type: "address",
                  internalType: "address",
                },
                {
                  name: "variableDebtTokenAddress",
                  type: "address",
                  internalType: "address",
                },
                {
                  name: "interestRateStrategyAddress",
                  type: "address",
                  internalType: "address",
                },
                {
                  name: "accruedToTreasury",
                  type: "uint128",
                  internalType: "uint128",
                },
                {
                  name: "unbacked",
                  type: "uint128",
                  internalType: "uint128",
                },
                {
                  name: "isolationModeTotalDebt",
                  type: "uint128",
                  internalType: "uint128",
                },
              ],
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getReserveNormalizedIncome",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getReserveNormalizedVariableDebt",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getReservesList",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "address[]",
              internalType: "address[]",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getUserAccountData",
          inputs: [
            {
              name: "user",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "totalCollateralBase",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "totalDebtBase",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "availableBorrowsBase",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "currentLiquidationThreshold",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "ltv",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "healthFactor",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getUserConfiguration",
          inputs: [
            {
              name: "user",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "tuple",
              internalType: "struct DataTypes.UserConfigurationMap",
              components: [
                {
                  name: "data",
                  type: "uint256",
                  internalType: "uint256",
                },
              ],
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getUserEMode",
          inputs: [
            {
              name: "user",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "initReserve",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "aTokenAddress",
              type: "address",
              internalType: "address",
            },
            {
              name: "stableDebtAddress",
              type: "address",
              internalType: "address",
            },
            {
              name: "variableDebtAddress",
              type: "address",
              internalType: "address",
            },
            {
              name: "interestRateStrategyAddress",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "liquidationCall",
          inputs: [
            {
              name: "collateralAsset",
              type: "address",
              internalType: "address",
            },
            {
              name: "debtAsset",
              type: "address",
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              internalType: "address",
            },
            {
              name: "debtToCover",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "receiveAToken",
              type: "bool",
              internalType: "bool",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "mintToTreasury",
          inputs: [
            {
              name: "assets",
              type: "address[]",
              internalType: "address[]",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "mintUnbacked",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "onBehalfOf",
              type: "address",
              internalType: "address",
            },
            {
              name: "referralCode",
              type: "uint16",
              internalType: "uint16",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "rebalanceStableBorrowRate",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "repay",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "interestRateMode",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "onBehalfOf",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "repayWithATokens",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "interestRateMode",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "repayWithPermit",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "interestRateMode",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "onBehalfOf",
              type: "address",
              internalType: "address",
            },
            {
              name: "deadline",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "permitV",
              type: "uint8",
              internalType: "uint8",
            },
            {
              name: "permitR",
              type: "bytes32",
              internalType: "bytes32",
            },
            {
              name: "permitS",
              type: "bytes32",
              internalType: "bytes32",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "rescueTokens",
          inputs: [
            {
              name: "token",
              type: "address",
              internalType: "address",
            },
            {
              name: "to",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "resetIsolationModeTotalDebt",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "setConfiguration",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "configuration",
              type: "tuple",
              internalType: "struct DataTypes.ReserveConfigurationMap",
              components: [
                {
                  name: "data",
                  type: "uint256",
                  internalType: "uint256",
                },
              ],
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "setReserveInterestRateStrategyAddress",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "rateStrategyAddress",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "setUserEMode",
          inputs: [
            {
              name: "categoryId",
              type: "uint8",
              internalType: "uint8",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "setUserUseReserveAsCollateral",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "useAsCollateral",
              type: "bool",
              internalType: "bool",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "supply",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "onBehalfOf",
              type: "address",
              internalType: "address",
            },
            {
              name: "referralCode",
              type: "uint16",
              internalType: "uint16",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "supplyWithPermit",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "onBehalfOf",
              type: "address",
              internalType: "address",
            },
            {
              name: "referralCode",
              type: "uint16",
              internalType: "uint16",
            },
            {
              name: "deadline",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "permitV",
              type: "uint8",
              internalType: "uint8",
            },
            {
              name: "permitR",
              type: "bytes32",
              internalType: "bytes32",
            },
            {
              name: "permitS",
              type: "bytes32",
              internalType: "bytes32",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "swapBorrowRateMode",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "interestRateMode",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "updateBridgeProtocolFee",
          inputs: [
            {
              name: "bridgeProtocolFee",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "updateFlashloanPremiums",
          inputs: [
            {
              name: "flashLoanPremiumTotal",
              type: "uint128",
              internalType: "uint128",
            },
            {
              name: "flashLoanPremiumToProtocol",
              type: "uint128",
              internalType: "uint128",
            },
          ],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "withdraw",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "to",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "event",
          name: "BackUnbacked",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "backer",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "fee",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "Borrow",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              indexed: false,
              internalType: "address",
            },
            {
              name: "onBehalfOf",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "interestRateMode",
              type: "uint8",
              indexed: false,
              internalType: "enum DataTypes.InterestRateMode",
            },
            {
              name: "borrowRate",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "referralCode",
              type: "uint16",
              indexed: true,
              internalType: "uint16",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "FlashLoan",
          inputs: [
            {
              name: "target",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "initiator",
              type: "address",
              indexed: false,
              internalType: "address",
            },
            {
              name: "asset",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "interestRateMode",
              type: "uint8",
              indexed: false,
              internalType: "enum DataTypes.InterestRateMode",
            },
            {
              name: "premium",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "referralCode",
              type: "uint16",
              indexed: true,
              internalType: "uint16",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "IsolationModeTotalDebtUpdated",
          inputs: [
            {
              name: "asset",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "totalDebt",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "LiquidationCall",
          inputs: [
            {
              name: "collateralAsset",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "debtAsset",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "debtToCover",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "liquidatedCollateralAmount",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "liquidator",
              type: "address",
              indexed: false,
              internalType: "address",
            },
            {
              name: "receiveAToken",
              type: "bool",
              indexed: false,
              internalType: "bool",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "MintUnbacked",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              indexed: false,
              internalType: "address",
            },
            {
              name: "onBehalfOf",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "referralCode",
              type: "uint16",
              indexed: true,
              internalType: "uint16",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "MintedToTreasury",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "amountMinted",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "RebalanceStableBorrowRate",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              indexed: true,
              internalType: "address",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "Repay",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "repayer",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "useATokens",
              type: "bool",
              indexed: false,
              internalType: "bool",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "ReserveDataUpdated",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "liquidityRate",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "stableBorrowRate",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "variableBorrowRate",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "liquidityIndex",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "variableBorrowIndex",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "ReserveUsedAsCollateralDisabled",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              indexed: true,
              internalType: "address",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "ReserveUsedAsCollateralEnabled",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              indexed: true,
              internalType: "address",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "Supply",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              indexed: false,
              internalType: "address",
            },
            {
              name: "onBehalfOf",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
            {
              name: "referralCode",
              type: "uint16",
              indexed: true,
              internalType: "uint16",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "SwapBorrowRateMode",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "interestRateMode",
              type: "uint8",
              indexed: false,
              internalType: "enum DataTypes.InterestRateMode",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "UserEModeSet",
          inputs: [
            {
              name: "user",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "categoryId",
              type: "uint8",
              indexed: false,
              internalType: "uint8",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "Withdraw",
          inputs: [
            {
              name: "reserve",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "to",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "amount",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
          ],
          anonymous: false,
        },
      ],
    },
    IPoolDataProvider: {
      address: "0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3",
      abi: [
        {
          type: "function",
          name: "ADDRESSES_PROVIDER",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "address",
              internalType: "contract IPoolAddressesProvider",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getATokenTotalSupply",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getAllATokens",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "tuple[]",
              internalType: "struct IPoolDataProvider.TokenData[]",
              components: [
                {
                  name: "symbol",
                  type: "string",
                  internalType: "string",
                },
                {
                  name: "tokenAddress",
                  type: "address",
                  internalType: "address",
                },
              ],
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getAllReservesTokens",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "tuple[]",
              internalType: "struct IPoolDataProvider.TokenData[]",
              components: [
                {
                  name: "symbol",
                  type: "string",
                  internalType: "string",
                },
                {
                  name: "tokenAddress",
                  type: "address",
                  internalType: "address",
                },
              ],
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getDebtCeiling",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getDebtCeilingDecimals",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "pure",
        },
        {
          type: "function",
          name: "getFlashLoanEnabled",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getInterestRateStrategyAddress",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "irStrategyAddress",
              type: "address",
              internalType: "address",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getLiquidationProtocolFee",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getPaused",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "isPaused",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getReserveCaps",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "borrowCap",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "supplyCap",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getReserveConfigurationData",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "decimals",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "ltv",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "liquidationThreshold",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "liquidationBonus",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "reserveFactor",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "usageAsCollateralEnabled",
              type: "bool",
              internalType: "bool",
            },
            {
              name: "borrowingEnabled",
              type: "bool",
              internalType: "bool",
            },
            {
              name: "stableBorrowRateEnabled",
              type: "bool",
              internalType: "bool",
            },
            {
              name: "isActive",
              type: "bool",
              internalType: "bool",
            },
            {
              name: "isFrozen",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getReserveData",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "unbacked",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "accruedToTreasuryScaled",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "totalAToken",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "totalStableDebt",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "totalVariableDebt",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "liquidityRate",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "variableBorrowRate",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "stableBorrowRate",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "averageStableBorrowRate",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "liquidityIndex",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "variableBorrowIndex",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "lastUpdateTimestamp",
              type: "uint40",
              internalType: "uint40",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getReserveEModeCategory",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getReserveTokensAddresses",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "aTokenAddress",
              type: "address",
              internalType: "address",
            },
            {
              name: "stableDebtTokenAddress",
              type: "address",
              internalType: "address",
            },
            {
              name: "variableDebtTokenAddress",
              type: "address",
              internalType: "address",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getSiloedBorrowing",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getTotalDebt",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getUnbackedMintCap",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getUserReserveData",
          inputs: [
            {
              name: "asset",
              type: "address",
              internalType: "address",
            },
            {
              name: "user",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "currentATokenBalance",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "currentStableDebt",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "currentVariableDebt",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "principalStableDebt",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "scaledVariableDebt",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "stableBorrowRate",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "liquidityRate",
              type: "uint256",
              internalType: "uint256",
            },
            {
              name: "stableRateLastUpdated",
              type: "uint40",
              internalType: "uint40",
            },
            {
              name: "usageAsCollateralEnabled",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "view",
        },
      ],
    },
    USDC: {
      address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      abi: [
        {
          type: "function",
          name: "allowance",
          inputs: [
            {
              name: "owner",
              type: "address",
              internalType: "address",
            },
            {
              name: "spender",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "approve",
          inputs: [
            {
              name: "spender",
              type: "address",
              internalType: "address",
            },
            {
              name: "value",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "balanceOf",
          inputs: [
            {
              name: "account",
              type: "address",
              internalType: "address",
            },
          ],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "totalSupply",
          inputs: [],
          outputs: [
            {
              name: "",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "transfer",
          inputs: [
            {
              name: "to",
              type: "address",
              internalType: "address",
            },
            {
              name: "value",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "transferFrom",
          inputs: [
            {
              name: "from",
              type: "address",
              internalType: "address",
            },
            {
              name: "to",
              type: "address",
              internalType: "address",
            },
            {
              name: "value",
              type: "uint256",
              internalType: "uint256",
            },
          ],
          outputs: [
            {
              name: "",
              type: "bool",
              internalType: "bool",
            },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "event",
          name: "Approval",
          inputs: [
            {
              name: "owner",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "spender",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "value",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
          ],
          anonymous: false,
        },
        {
          type: "event",
          name: "Transfer",
          inputs: [
            {
              name: "from",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "to",
              type: "address",
              indexed: true,
              internalType: "address",
            },
            {
              name: "value",
              type: "uint256",
              indexed: false,
              internalType: "uint256",
            },
          ],
          anonymous: false,
        },
      ],
    },
  },
} as const;

export default externalContracts satisfies GenericContractsDeclaration;
