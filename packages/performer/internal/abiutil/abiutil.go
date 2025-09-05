package abiutil

import (
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/accounts/abi"
)

var (
	u256Type, _   = abi.NewType("uint256", "", nil)
	boolType, _   = abi.NewType("bool", "", nil)
	stringType, _ = abi.NewType("string", "", nil)
	statusType, _ = abi.NewType("uint8", "", nil)

	payloadArgs = abi.Arguments{
		{Type: u256Type},
		{Type: stringType},
	}
	// Result encoded as (uint256, bool, uint8)
	resultArgs = abi.Arguments{
		{Type: u256Type},
		{Type: boolType},
		{Type: statusType},
	}
)

func DecodeVerifyPayload(payload []byte) (*big.Int, string, error) {
	vals, err := payloadArgs.Unpack(payload)
	if err != nil {
		return nil, "", fmt.Errorf("failed to decode payload: %w", err)
	}
	if len(vals) != 2 {
		return nil, "", fmt.Errorf("unexpected payload items: %d", len(vals))
	}
	id, ok := vals[0].(*big.Int)
	if !ok {
		return nil, "", fmt.Errorf("payload[0] not big.Int")
	}
	newUri, ok := vals[1].(string)
	if !ok {
		return nil, "", fmt.Errorf("payload[1] not string")
	}
	return id, newUri, nil
}

func EncodeResult(tokenId *big.Int, valid bool, status uint8) ([]byte, error) {
	encoded, err := resultArgs.Pack(tokenId, valid, status)
	if err != nil {
		return nil, fmt.Errorf("failed to encode result: %w", err)
	}
	return encoded, nil
}
