package main

import (
	"context"
	"fmt"
	"time"

	"github.com/Layr-Labs/hourglass-monorepo/ponos/pkg/performer/server"
	"go.uber.org/zap"

	appcfg "github.com/liquid-ip/performer/internal/config"
	appworker "github.com/liquid-ip/performer/internal/worker"
)

func main() {
	l, _ := zap.NewProduction()
	defer l.Sync()

	cfg, err := appcfg.Load()
	if err != nil {
		l.Sugar().Fatalw("invalid configuration", "error", err)
	}

	l.Sugar().Infow("starting performer",
		"rpc", cfg.RpcURL,
		"erc721", cfg.Erc721PatentRegistryAddress,
		"ipfs", cfg.IpfsGateway,
		"schema", cfg.SchemaURI,
		"port", cfg.Port,
	)

	w, err := appworker.NewVerifierWorker(l, cfg)
	if err != nil {
		l.Sugar().Fatalw("failed to init worker", "error", err)
	}
	pp, err := server.NewPonosPerformerWithRpcServer(&server.PonosPerformerConfig{
		Port:    cfg.Port,
		Timeout: 5 * time.Second,
	}, w, l)
	if err != nil {
		panic(fmt.Errorf("failed to create performer: %w", err))
	}

	ctx := context.Background()
	if err := pp.Start(ctx); err != nil {
		l.Sugar().Fatalw("performer exited", "error", err)
	}
}
