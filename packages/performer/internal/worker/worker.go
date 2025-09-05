package worker

import (
	"context"
	"math/big"
	"time"

	"github.com/Layr-Labs/protocol-apis/gen/protos/eigenlayer/hourglass/v1/performer"
	"github.com/ethereum/go-ethereum/common"
	"go.uber.org/zap"

	"github.com/liquid-ip/performer/internal/abiutil"
	"github.com/liquid-ip/performer/internal/config"
	ethcli "github.com/liquid-ip/performer/internal/eth"
	ipfscli "github.com/liquid-ip/performer/internal/ipfs"
	"github.com/liquid-ip/performer/internal/jsonval"
)

type VerifierWorker struct {
	logger   *zap.Logger
	cfg      *config.Config
	ipfs     *ipfscli.Client
	eth      *ethcli.Client
	maxFetch int64
}

func NewVerifierWorker(l *zap.Logger, cfg *config.Config) (*VerifierWorker, error) {
	ip := ipfscli.NewClient(cfg.IpfsGateway)
	eth, err := ethcli.NewClient(cfg.RpcURL)
	if err != nil {
		return nil, err
	}
	return &VerifierWorker{logger: l, cfg: cfg, ipfs: ip, eth: eth, maxFetch: 5 << 20}, nil // 5MB cap
}

func (w *VerifierWorker) ValidateTask(t *performer.TaskRequest) error {
	_, _, err := abiutil.DecodeVerifyPayload(t.Payload)
	return err
}

func (w *VerifierWorker) HandleTask(t *performer.TaskRequest) (*performer.TaskResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	id, newUri, err := abiutil.DecodeVerifyPayload(t.Payload)
	if err != nil {
		return w.result(t.TaskId, id, false, 0)
	}

	// fetch old tokenURI from ERC721
	oldURI, err := w.eth.TokenURI(ctx, common.HexToAddress(w.cfg.Erc721PatentRegistryAddress), id)
	if err != nil {
		return w.result(t.TaskId, id, false, 0)
	}
	oldB, err := w.ipfs.Fetch(ctx, oldURI, w.maxFetch)
	if err != nil {
		return w.result(t.TaskId, id, false, 0)
	}
	newB, err := w.ipfs.Fetch(ctx, newUri, w.maxFetch)
	if err != nil {
		return w.result(t.TaskId, id, false, 0)
	}

	// parse JSONs
	oldM, err := jsonval.Parse(oldB)
	if err != nil {
		return w.result(t.TaskId, id, false, 0)
	}
	newM, err := jsonval.Parse(newB)
	if err != nil {
		return w.result(t.TaskId, id, false, 0)
	}

	// schema optional
	var schemaM jsonval.JSONMap = nil
	if w.cfg.SchemaURI != "" {
		schemaB, err := w.ipfs.Fetch(ctx, w.cfg.SchemaURI, w.maxFetch)
		if err != nil {
			return w.result(t.TaskId, id, false, 0)
		}
		schemaM, err = jsonval.Parse(schemaB)
		if err != nil {
			return w.result(t.TaskId, id, false, 0)
		}
	}

	if !jsonval.PlaceholderValidate(oldM, newM, schemaM) {
		return w.result(t.TaskId, id, false, 0)
	}
	status, err := jsonval.StatusFromJSON(newM)
	if err != nil {
		return w.result(t.TaskId, id, false, 0)
	}
	return w.result(t.TaskId, id, true, status)
}

func (w *VerifierWorker) result(taskId []byte, tokenId *big.Int, valid bool, status uint8) (*performer.TaskResponse, error) {
	if tokenId == nil {
		tokenId = big.NewInt(0)
	}
	enc, _ := abiutil.EncodeResult(tokenId, valid, status)
	return &performer.TaskResponse{
		TaskId: taskId,
		Result: enc,
	}, nil
}
