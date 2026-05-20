// Example 07: External-signer flow — public file + single-chunk publish.
//
// PR #90 added PrepareUploadPublic / FinalizeUpload and PrepareChunkUpload /
// FinalizeChunkUpload so the wallet key never has to live in the antd daemon.
// This example uses anvil deterministic account #0 as the external signer
// and exercises both round-trips end-to-end.
//
// See docs/external-signer-flow.md for the full reference; the IPaymentVault
// contract ABI is loaded from docs/abi/IPaymentVault.json.
package main

import (
	"bytes"
	"context"
	"encoding/hex"
	"fmt"
	"log"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"time"

	antd "github.com/WithAutonomi/ant-sdk/antd-go"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

// Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
// (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
// use this key anywhere except a throw-away local devnet.
const anvilKey = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

// Minimal ERC-20 ABI for approve(). antToken is a standard ERC-20.
const erc20ABI = `[{"name":"approve","type":"function","stateMutability":"nonpayable",
  "inputs":[{"name":"spender","type":"address"},{"name":"value","type":"uint256"}],
  "outputs":[{"type":"bool"}]}]`

// DataPayment mirrors the IPaymentVault contract's struct for ABI encoding.
// Field names + types match the ABI's struct definition exactly so go-ethereum's
// abi.Pack reflection can encode/decode in either direction.
type DataPayment struct {
	RewardsAddress common.Address
	Amount         *big.Int
	QuoteHash      [32]byte
}

// externalSignerPay runs approve + payForQuotes on-chain for a daemon prepare
// response. Returns the quote_hash -> tx_hash map the daemon's Finalize*
// methods expect. Every entry maps to the same payForQuotes tx because every
// quote in the wave is paid in one batched call.
func externalSignerPay(ctx context.Context, rpcURL string, vaultAddr, tokenAddr common.Address, payments []antd.PaymentInfo, vaultABI abi.ABI) (map[string]string, error) {
	// No on-chain work when every quoted chunk is already on-network.
	if len(payments) == 0 {
		return map[string]string{}, nil
	}

	ec, err := ethclient.DialContext(ctx, rpcURL)
	if err != nil {
		return nil, fmt.Errorf("dial rpc: %w", err)
	}
	defer ec.Close()

	chainID, err := ec.ChainID(ctx)
	if err != nil {
		return nil, fmt.Errorf("chain id: %w", err)
	}
	priv, err := crypto.HexToECDSA(anvilKey)
	if err != nil {
		return nil, fmt.Errorf("parse key: %w", err)
	}
	auth, err := bind.NewKeyedTransactorWithChainID(priv, chainID)
	if err != nil {
		return nil, fmt.Errorf("auth: %w", err)
	}
	auth.Context = ctx

	erc20, err := abi.JSON(strings.NewReader(erc20ABI))
	if err != nil {
		return nil, fmt.Errorf("parse erc20 abi: %w", err)
	}

	// approve(vault, MAX) — idempotent and cheap; example uses MAX so
	// subsequent flows in this run skip a fresh approval.
	maxUint256 := new(big.Int).Sub(new(big.Int).Lsh(big.NewInt(1), 256), big.NewInt(1))
	token := bind.NewBoundContract(tokenAddr, erc20, ec, ec, ec)
	approveTx, err := token.Transact(auth, "approve", vaultAddr, maxUint256)
	if err != nil {
		return nil, fmt.Errorf("approve: %w", err)
	}
	if _, err := bind.WaitMined(ctx, ec, approveTx); err != nil {
		return nil, fmt.Errorf("approve mined: %w", err)
	}

	// payForQuotes — one tx covering every quote in this wave.
	dps := make([]DataPayment, len(payments))
	for i, p := range payments {
		amt, ok := new(big.Int).SetString(p.Amount, 10)
		if !ok {
			return nil, fmt.Errorf("parse amount %q", p.Amount)
		}
		qhHex := strings.TrimPrefix(p.QuoteHash, "0x")
		qhBytes, err := hex.DecodeString(qhHex)
		if err != nil {
			return nil, fmt.Errorf("decode quote_hash: %w", err)
		}
		var qh [32]byte
		copy(qh[:], qhBytes)
		dps[i] = DataPayment{
			RewardsAddress: common.HexToAddress(p.RewardsAddress),
			Amount:         amt,
			QuoteHash:      qh,
		}
	}
	vault := bind.NewBoundContract(vaultAddr, vaultABI, ec, ec, ec)
	payTx, err := vault.Transact(auth, "payForQuotes", dps)
	if err != nil {
		return nil, fmt.Errorf("payForQuotes: %w", err)
	}
	if _, err := bind.WaitMined(ctx, ec, payTx); err != nil {
		return nil, fmt.Errorf("payForQuotes mined: %w", err)
	}

	// Every quote in this wave was paid in the same call.
	txHash := payTx.Hash().Hex()
	out := make(map[string]string, len(payments))
	for _, p := range payments {
		out[p.QuoteHash] = txHash
	}
	return out, nil
}

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	client := antd.NewClient(antd.DefaultBaseURL)

	// Locate docs/abi/IPaymentVault.json relative to repo root.
	repoRoot, err := findRepoRoot()
	if err != nil {
		log.Fatalf("find repo root: %v", err)
	}
	abiBytes, err := os.ReadFile(filepath.Join(repoRoot, "docs", "abi", "IPaymentVault.json"))
	if err != nil {
		log.Fatalf("read vault abi: %v", err)
	}
	vaultABI, err := abi.JSON(bytes.NewReader(abiBytes))
	if err != nil {
		log.Fatalf("parse vault abi: %v", err)
	}

	tmpDir, err := os.MkdirTemp("", "antd-go-07-extsig-*")
	if err != nil {
		log.Fatalf("mkdir temp: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// --- 1. file upload via external signer ---------------------------
	srcPath := filepath.Join(tmpDir, "file.bin")
	fileContent := bytes.Repeat([]byte("hello external signer from go (file)\n"), 16)
	if err := os.WriteFile(srcPath, fileContent, 0o600); err != nil {
		log.Fatalf("write source: %v", err)
	}

	filePrep, err := client.PrepareUploadPublic(ctx, srcPath)
	if err != nil {
		log.Fatalf("prepare upload public: %v", err)
	}
	fmt.Printf("File prepare: upload_id=%s..., payment_type=%s, payments=%d, total_amount=%s\n",
		filePrep.UploadID[:16], filePrep.PaymentType, len(filePrep.Payments), filePrep.TotalAmount)

	txHashes, err := externalSignerPay(ctx, filePrep.RPCUrl,
		common.HexToAddress(filePrep.PaymentVaultAddress),
		common.HexToAddress(filePrep.PaymentTokenAddress),
		filePrep.Payments, vaultABI)
	if err != nil {
		log.Fatalf("file external signer pay: %v", err)
	}
	fileFin, err := client.FinalizeUpload(ctx, filePrep.UploadID, txHashes, false)
	if err != nil {
		log.Fatalf("finalize upload: %v", err)
	}
	fmt.Printf("File finalize: data_map_address=%s, chunks_stored=%d\n",
		fileFin.DataMapAddress, fileFin.ChunksStored)

	dstPath := srcPath + ".downloaded"
	if err := client.FileGetPublic(ctx, fileFin.DataMapAddress, dstPath); err != nil {
		log.Fatalf("file download: %v", err)
	}
	got, err := os.ReadFile(dstPath)
	if err != nil {
		log.Fatalf("read downloaded: %v", err)
	}
	if !bytes.Equal(got, fileContent) {
		log.Fatalf("file round-trip mismatch")
	}
	fmt.Println("File round-trip OK!")

	// --- 2. single-chunk publish via external signer ------------------
	chunkData := bytes.Repeat([]byte("hello external signer from go (chunk)\n"), 8)
	chunkPrep, err := client.PrepareChunkUpload(ctx, chunkData)
	if err != nil {
		log.Fatalf("prepare chunk: %v", err)
	}
	if chunkPrep.AlreadyStored {
		fmt.Printf("Chunk prepare: already_stored, address=%s\n", chunkPrep.Address)
	} else {
		fmt.Printf("Chunk prepare: upload_id=%s..., address=%s, payments=%d, total_amount=%s\n",
			chunkPrep.UploadID[:16], chunkPrep.Address, len(chunkPrep.Payments), chunkPrep.TotalAmount)
		txHashes, err := externalSignerPay(ctx, chunkPrep.RPCUrl,
			common.HexToAddress(chunkPrep.PaymentVaultAddress),
			common.HexToAddress(chunkPrep.PaymentTokenAddress),
			chunkPrep.Payments, vaultABI)
		if err != nil {
			log.Fatalf("chunk external signer pay: %v", err)
		}
		addr, err := client.FinalizeChunkUpload(ctx, chunkPrep.UploadID, txHashes)
		if err != nil {
			log.Fatalf("finalize chunk: %v", err)
		}
		if addr != chunkPrep.Address {
			log.Fatalf("chunk address mismatch: %s != %s", addr, chunkPrep.Address)
		}
		fmt.Printf("Chunk finalize: address=%s\n", addr)
	}

	chunkGot, err := client.ChunkGet(ctx, chunkPrep.Address)
	if err != nil {
		log.Fatalf("chunk get: %v", err)
	}
	if !bytes.Equal(chunkGot, chunkData) {
		log.Fatalf("chunk round-trip mismatch")
	}
	fmt.Println("Chunk round-trip OK!")

	fmt.Println("\n07-external-signer OK!")
}

// findRepoRoot walks up from cwd looking for the docs/abi/IPaymentVault.json
// path bundled in the repo. Used to locate the ABI without hardcoding paths.
func findRepoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for i := 0; i < 8; i++ {
		if _, err := os.Stat(filepath.Join(dir, "docs", "abi", "IPaymentVault.json")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", fmt.Errorf("could not find docs/abi/IPaymentVault.json above cwd")
}
