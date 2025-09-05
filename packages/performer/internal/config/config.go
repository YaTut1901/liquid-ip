package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	RpcURL                      string
	Erc721PatentRegistryAddress string
	IpfsGateway                 string
	SchemaURI                   string
	Port                        int
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func Load() (*Config, error) {
	cfg := &Config{
		RpcURL:                      getenv("PERFORMER_RPC_URL", ""),
		Erc721PatentRegistryAddress: getenv("PERFORMER_ERC721_PATENT_REGISTRY_ADDRESS", ""),
		IpfsGateway:                 getenv("PERFORMER_IPFS_GATEWAY", ""),
		SchemaURI:                   getenv("PERFORMER_SCHEMA_URI", ""),
	}
	portStr := getenv("PERFORMER_PORT", "8080")
	p, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, fmt.Errorf("invalid PERFORMER_PORT: %w", err)
	}
	cfg.Port = p
	if err := cfg.Validate(); err != nil {
		return nil, err
	}
	return cfg, nil
}

func (c *Config) Validate() error {
	missing := func(k string) error { return fmt.Errorf("missing %s", k) }
	if c.RpcURL == "" {
		return missing("PERFORMER_RPC_URL")
	}
	if c.Erc721PatentRegistryAddress == "" {
		return missing("PERFORMER_ERC721_PATENT_REGISTRY_ADDRESS")
	}
	if c.IpfsGateway == "" {
		return missing("PERFORMER_IPFS_GATEWAY")
	}
	// SchemaURI is optional; when empty, worker skips schema fetch
	return nil
}
