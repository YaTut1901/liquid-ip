package eth

import (
	"context"
	"fmt"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

type Client struct {
	rpc *ethclient.Client
}

func NewClient(rpcURL string) (*Client, error) {
	c, err := ethclient.Dial(rpcURL)
	if err != nil {
		return nil, fmt.Errorf("failed to dial rpc: %w", err)
	}
	return &Client{rpc: c}, nil
}

var erc721MetadataABI = `[{"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"tokenURI","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"}]`

func (c *Client) TokenURI(ctx context.Context, contract common.Address, tokenId *big.Int) (string, error) {
	parsed, err := abi.JSON(strings.NewReader(erc721MetadataABI))
	if err != nil {
		return "", fmt.Errorf("parse abi: %w", err)
	}
	bound := bind.NewBoundContract(contract, parsed, c.rpc, c.rpc, c.rpc)
	var out []interface{}
	if err := bound.Call(&bind.CallOpts{Context: ctx}, &out, "tokenURI", tokenId); err != nil {
		return "", fmt.Errorf("call tokenURI: %w", err)
	}
	if len(out) != 1 {
		return "", fmt.Errorf("unexpected outputs: %d", len(out))
	}
	uri, ok := out[0].(string)
	if !ok {
		return "", fmt.Errorf("tokenURI not string")
	}
	return uri, nil
}
