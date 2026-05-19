<?php

/**
 * Example 07: External-signer flow — public file + single-chunk publish.
 *
 * PR #90 added prepareUploadPublic / finalizeUpload and prepareChunkUpload /
 * finalizeChunkUpload so the wallet key never has to live in the antd
 * daemon. This example uses anvil deterministic account #0 as the external
 * signer and exercises both round-trips end-to-end.
 *
 * See docs/external-signer-flow.md for the full reference; the IPaymentVault
 * function selector and tuple ABI are encoded inline via web3p/ethereum-abi.
 *
 * Requires:
 *   - web3p/ethereum-tx   (EIP-1559 tx signing)
 *   - web3p/ethereum-util (keccak256 + address derivation)
 *   - guzzlehttp/guzzle   (HTTP for JSON-RPC, already a runtime dep)
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Autonomi\Antd\AntdClient;
use Web3p\EthereumTx\EIP1559Transaction;
use GuzzleHttp\Client as HttpClient;

// Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
// (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
// use this key anywhere except a throw-away local devnet.
const ANVIL_KEY = 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const ANVIL_ADDRESS = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

// payForQuotes selector. See docs/external-signer-flow.md.
const PAY_FOR_QUOTES_SELECTOR = '0xb6c2141b';
// ERC-20 approve(address,uint256) selector.
const APPROVE_SELECTOR = '0x095ea7b3';

/**
 * Run approve + payForQuotes on-chain for a daemon prepare response.
 * Returns the quote_hash -> tx_hash map the daemon's finalize_* methods
 * expect. Every entry maps to the same payForQuotes tx because every
 * quote in the wave is paid in one batched call.
 *
 * @param  array<\Autonomi\Antd\Models\PaymentInfo>  $payments
 * @return array<string,string>
 */
function externalSignerPay(string $rpcUrl, string $vaultAddr, string $tokenAddr, array $payments): array
{
    // No on-chain work when every quoted chunk is already on-network.
    if (count($payments) === 0) {
        return [];
    }

    $http = new HttpClient(['base_uri' => $rpcUrl, 'timeout' => 30.0]);
    $sender = ANVIL_ADDRESS;
    $chainId = rpcCall($http, 'eth_chainId', [])['result'];
    $gasPrice = rpcCall($http, 'eth_gasPrice', [])['result'];

    // approve(vault, MAX) — idempotent and cheap; example uses MAX so
    // subsequent flows in this run skip a fresh approval.
    $approveData = APPROVE_SELECTOR
        . padAddress($vaultAddr)
        . padUint(str_repeat('f', 64));  // MAX_UINT256
    sendAndWait($http, $sender, $tokenAddr, $approveData, $chainId, $gasPrice, '0x' . dechex(500000));

    // payForQuotes((address rewardsAddress, uint256 amount, bytes32 quoteHash)[])
    // Encoding: [4-byte selector] [32-byte offset=0x20] [32-byte length=N]
    // [N x (address pad32 + amount pad32 + bytes32 pad32)]
    $count = count($payments);
    $body = padUint(dechex(0x20))   // offset to dynamic array
          . padUint(dechex($count)); // array length
    foreach ($payments as $p) {
        $amountHex = gmp_strval(gmp_init($p->amount, 10), 16);
        $qhHex = $p->quoteHash;
        if (str_starts_with($qhHex, '0x')) {
            $qhHex = substr($qhHex, 2);
        }
        $body .= padAddress($p->rewardsAddress)
              .  padUint($amountHex)
              .  $qhHex;  // bytes32 is already raw 32 bytes
    }
    $payData = PAY_FOR_QUOTES_SELECTOR . $body;
    $payTxHash = sendAndWait($http, $sender, $vaultAddr, $payData, $chainId, $gasPrice, '0x' . dechex(1000000));

    // Every quote in this wave was paid in the same call.
    $out = [];
    foreach ($payments as $p) {
        $out[$p->quoteHash] = $payTxHash;
    }
    return $out;
}

function rpcCall(HttpClient $http, string $method, array $params): array
{
    static $id = 0;
    $id++;
    $rsp = $http->post('', [
        'json' => ['jsonrpc' => '2.0', 'id' => $id, 'method' => $method, 'params' => $params],
        'headers' => ['Content-Type' => 'application/json'],
    ]);
    $j = json_decode($rsp->getBody()->getContents(), true);
    if (isset($j['error'])) {
        throw new \RuntimeException("$method error: " . json_encode($j['error']));
    }
    return $j;
}

function sendAndWait(HttpClient $http, string $from, string $to, string $data, string $chainIdHex, string $gasPriceHex, string $gasLimitHex): string
{
    $nonceHex = rpcCall($http, 'eth_getTransactionCount', [$from, 'pending'])['result'];

    // web3p/ethereum-tx's EIP1559Transaction RLP-encodes in canonical EIP-1559
    // field order. accessList must be present (empty list is fine) for the
    // RLP shape to be correct, otherwise anvil rejects with
    // "Failed to decode transaction".
    $tx = new EIP1559Transaction([
        'nonce'                => $nonceHex,
        'maxPriorityFeePerGas' => $gasPriceHex,
        'maxFeePerGas'         => '0x' . dechex(hexdec($gasPriceHex) * 2 + 1_000_000_000),
        'gasLimit'             => $gasLimitHex,
        'to'                   => $to,
        'value'                => '0x0',
        'data'                 => $data,
        'chainId'              => $chainIdHex,
        'accessList'           => [],
    ]);
    $signed = '0x' . $tx->sign(ANVIL_KEY);
    $txHash = rpcCall($http, 'eth_sendRawTransaction', [$signed])['result'];

    // Poll for receipt. Anvil instant-mines, so this typically resolves on
    // the first poll.
    for ($i = 0; $i < 600; $i++) {
        $r = rpcCall($http, 'eth_getTransactionReceipt', [$txHash]);
        if (isset($r['result']) && $r['result'] !== null) {
            if ($r['result']['status'] !== '0x1') {
                throw new \RuntimeException("tx $txHash reverted (status={$r['result']['status']})");
            }
            return $txHash;
        }
        usleep(100_000);  // 100 ms
    }
    throw new \RuntimeException("tx receipt timeout: $txHash");
}

function padAddress(string $addr): string
{
    $hex = strtolower(str_starts_with($addr, '0x') ? substr($addr, 2) : $addr);
    return str_repeat('0', 64 - strlen($hex)) . $hex;
}

function padUint(string $hex): string
{
    $hex = strtolower($hex);
    return str_repeat('0', 64 - strlen($hex)) . $hex;
}

// --- main ---

$tmp = sys_get_temp_dir() . DIRECTORY_SEPARATOR . uniqid('antd-php-07-extsig-');
mkdir($tmp, 0o700, true);
$client = new AntdClient();

try {
    // --- 1. file upload via external signer -------------------------------
    $srcFile = $tmp . '/file.bin';
    $fileContent = str_repeat("hello external signer from php (file)\n", 16);
    file_put_contents($srcFile, $fileContent);

    $filePrep = $client->prepareUploadPublic($srcFile);
    printf(
        "File prepare: upload_id=%s..., payment_type=%s, payments=%d, total_amount=%s\n",
        substr($filePrep->uploadId, 0, 16),
        $filePrep->paymentType,
        count($filePrep->payments),
        $filePrep->totalAmount
    );

    $fileTxHashes = externalSignerPay(
        $filePrep->rpcUrl,
        $filePrep->paymentVaultAddress,
        $filePrep->paymentTokenAddress,
        $filePrep->payments
    );
    $fileFin = $client->finalizeUpload($filePrep->uploadId, $fileTxHashes);
    printf(
        "File finalize: data_map_address=%s, chunks_stored=%d\n",
        $fileFin->dataMapAddress,
        $fileFin->chunksStored
    );

    $dstFile = $srcFile . '.downloaded';
    $client->fileDownloadPublic($fileFin->dataMapAddress, $dstFile);
    if (file_get_contents($dstFile) !== $fileContent) {
        fwrite(STDERR, "file round-trip mismatch\n");
        exit(1);
    }
    echo "File round-trip OK!\n";

    // --- 2. single-chunk publish via external signer ----------------------
    $chunkData = str_repeat("hello external signer from php (chunk)\n", 8);
    $chunkPrep = $client->prepareChunkUpload($chunkData);
    if ($chunkPrep->alreadyStored) {
        printf("Chunk prepare: already_stored, address=%s\n", $chunkPrep->address);
    } else {
        printf(
            "Chunk prepare: upload_id=%s..., address=%s, payments=%d, total_amount=%s\n",
            substr($chunkPrep->uploadId, 0, 16),
            $chunkPrep->address,
            count($chunkPrep->payments),
            $chunkPrep->totalAmount
        );
        $chunkTxHashes = externalSignerPay(
            $chunkPrep->rpcUrl,
            $chunkPrep->paymentVaultAddress,
            $chunkPrep->paymentTokenAddress,
            $chunkPrep->payments
        );
        $addr = $client->finalizeChunkUpload($chunkPrep->uploadId, $chunkTxHashes);
        if ($addr !== $chunkPrep->address) {
            fwrite(STDERR, "chunk address mismatch: {$addr} != {$chunkPrep->address}\n");
            exit(1);
        }
        printf("Chunk finalize: address=%s\n", $addr);
    }

    $chunkGot = $client->chunkGet($chunkPrep->address);
    if ($chunkGot !== $chunkData) {
        fwrite(STDERR, "chunk round-trip mismatch\n");
        exit(1);
    }
    echo "Chunk round-trip OK!\n";

    echo "\n07_external_signer OK!\n";
} finally {
    array_map('unlink', glob($tmp . '/*') ?: []);
    @rmdir($tmp);
}
