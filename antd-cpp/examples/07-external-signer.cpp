// Example 07: External-signer flow — public file + single-chunk publish.
//
// prepare_upload_public / finalize_upload and prepare_chunk_upload /
// finalize_chunk_upload let the wallet key live outside the antd daemon.
// This example uses anvil deterministic account #0 as the external signer
// and exercises both round-trips end-to-end.
//
// See docs/external-signer-flow.md for the full reference. C++ has no
// small, drift-proof EVM library for EIP-1559 + tuple ABI encoding +
// secp256k1 signing, so (like the Elixir example) this runs `cast` (foundry
// CLI), which `ant dev start --enable-evm` already depends on. `cast` is
// started with an argument vector, never through a shell, and every
// daemon-provided field is validated before it becomes an argument (see
// external_signer_util.hpp).
//
// Requires:
//   - a running antd daemon against a devnet with EVM enabled
//     (`ant dev start --enable-evm`)
//   - `cast` on PATH

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <nlohmann/json.hpp>

#include "antd/antd.hpp"
#include "external_signer_util.hpp"

namespace {

// Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
// (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
// use this key anywhere except a throw-away local devnet.
constexpr const char* kAnvilKey =
    "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
constexpr const char* kMaxUint256 =
    "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

// `cast send ... --json` and return the transactionHash. `cast` is started
// directly with this argument vector (antd_example::run_capture), so no
// argument is ever parsed by a shell; the daemon-provided ones have also
// passed validate_signing_request before this is called.
std::string cast_send(const std::string& rpc_url, const std::vector<std::string>& args,
                      const std::string& gas_limit) {
    std::vector<std::string> argv{"cast", "send"};
    argv.insert(argv.end(), args.begin(), args.end());
    argv.insert(argv.end(), {"--rpc-url", rpc_url, "--private-key", kAnvilKey,
                             "--gas-limit", gas_limit, "--json"});
    const auto receipt = nlohmann::json::parse(antd_example::run_capture(argv));
    std::string tx_hash = receipt.at("transactionHash").get<std::string>();
    if (!antd_example::is_bytes32_hex(tx_hash)) {
        throw std::runtime_error("cast returned a transactionHash that is not 32 bytes of hex");
    }
    return tx_hash;
}

// Run approve + payForQuotes on-chain for a daemon prepare response.
// Returns the quote_hash -> tx_hash map the daemon's finalize_* methods
// expect. Every entry maps to the same payForQuotes tx because every quote
// in the wave is paid in one batched call.
std::map<std::string, std::string> external_signer_pay(
    const std::string& rpc_url, const std::string& vault_addr,
    const std::string& token_addr, const std::vector<antd::PaymentInfo>& payments) {
    std::map<std::string, std::string> out;
    // No on-chain work when every quoted chunk is already on-network.
    if (payments.empty()) return out;

    // Reject a malformed or hostile prepare response before any of its
    // fields reaches a process.
    antd_example::validate_signing_request(rpc_url, vault_addr, token_addr, payments);

    // Idempotent unlimited approval so subsequent runs in the same devnet
    // session skip a fresh approve.
    cast_send(rpc_url, {token_addr, "approve(address,uint256)", vault_addr, kMaxUint256},
              "500000");

    // payForQuotes((address rewardsAddress, uint256 amount, bytes32 quoteHash)[])
    std::string tuples = "[";
    for (std::size_t i = 0; i < payments.size(); ++i) {
        const auto& p = payments[i];
        std::string qh = p.quote_hash;
        if (qh.rfind("0x", 0) != 0) qh = "0x" + qh;
        if (i) tuples += ",";
        tuples += "(" + p.rewards_address + "," + p.amount + "," + qh + ")";
    }
    tuples += "]";
    const auto tx_hash = cast_send(
        rpc_url, {vault_addr, "payForQuotes((address,uint256,bytes32)[])", tuples}, "1000000");

    for (const auto& p : payments) out[p.quote_hash] = tx_hash;
    return out;
}

// finalize_with_retry finalizes a wave-batch upload and, when the daemon
// reports a storage shortfall AFTER the payment settled, retries the same
// call against the same payment. antd >= 0.14.0 keeps the paid attempt
// (payment proofs + unstored chunks) under the same upload_id and flags the
// error `retryable`, so repeating finalize_upload stores only the remainder:
// no re-prepare, no second signature, no double payment.
//
// The loop is bounded: a persistent failure (a chunk whose close group stays
// unreachable) throws PartialUploadError on every call, never a different
// error, so it caps the attempts and treats a chunks_failed that stops
// shrinking as stuck. A non-retryable partial upload (older daemon, or a
// merkle upload with unpaid batches) is rethrown untouched: the recovery
// there is to re-prepare the same content, which skips the chunks already
// stored. Over gRPC, `retryable == false` can also mean the SDK could not
// read the daemon's message: retention is then unconfirmed, not proof the
// paid attempt was discarded, so do not treat it alone as permission to pay
// again. See docs/external-signer-flow.md section 6.
antd::FinalizeUploadResult finalize_with_retry(
    antd::Client& client, const std::string& upload_id,
    const std::map<std::string, std::string>& tx_hashes, bool store_data_map) {
    constexpr int kMaxAttempts = 5;
    std::uint64_t last_failed = 0;
    for (int attempt = 1;; ++attempt) {
        try {
            return client.finalize_upload(upload_id, tx_hashes, store_data_map);
        } catch (const antd::PartialUploadError& e) {
            if (!e.retryable) {
                throw;  // retention not confirmed: the caller decides (see above)
            }
            const bool stuck = attempt > 1 && e.chunks_failed >= last_failed;
            if (attempt >= kMaxAttempts || stuck) {
                // Keep the type (and counts) so callers can still branch on
                // PartialUploadError; only the message gains the diagnosis.
                throw antd::PartialUploadError(
                    "finalize stuck after " + std::to_string(attempt) + " attempt(s): " +
                        std::to_string(e.chunks_stored) + "/" + std::to_string(e.total_chunks) +
                        " chunks stored, " + std::to_string(e.chunks_failed) +
                        " still unstored (paid attempt retained under upload_id " + upload_id +
                        ", retry later or re-prepare): " + e.what(),
                    e.chunks_stored, e.chunks_failed, e.total_chunks, e.retryable);
            }
            last_failed = e.chunks_failed;
            std::cout << "finalize stored " << e.chunks_stored << "/" << e.total_chunks
                      << " chunks, " << e.chunks_failed
                      << " still unstored: retrying against the same payment (attempt "
                      << attempt + 1 << "/" << kMaxAttempts << ")\n";
            std::this_thread::sleep_for(std::chrono::seconds(2 * attempt));
        }
    }
}

std::string read_file(const std::filesystem::path& p) {
    std::ifstream in(p, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(in), {});
}

}  // namespace

int main() {
    namespace fs = std::filesystem;
    const fs::path tmp = fs::temp_directory_path() / "antd-cpp-07-extsig";
    fs::create_directories(tmp);

    try {
        antd::Client client;

        // --- 1. file upload via external signer ---------------------------
        const fs::path src = tmp / "file.bin";
        std::string file_content;
        for (int i = 0; i < 16; ++i) file_content += "hello external signer from c++ (file)\n";
        {
            std::ofstream out(src, std::ios::binary);
            out << file_content;
        }

        auto file_prep = client.prepare_upload_public(src.string());
        std::cout << "File prepare: upload_id=" << file_prep.upload_id.substr(0, 16)
                  << "..., payment_type=" << file_prep.payment_type
                  << ", payments=" << file_prep.payments.size()
                  << ", total_amount=" << file_prep.total_amount << "\n";

        auto file_tx_hashes = external_signer_pay(
            file_prep.rpc_url, file_prep.payment_vault_address,
            file_prep.payment_token_address, file_prep.payments);

        auto file_fin = finalize_with_retry(client, file_prep.upload_id, file_tx_hashes,
                                            /*store_data_map=*/false);
        std::cout << "File finalize: data_map_address=" << file_fin.data_map_address
                  << ", chunks_stored=" << file_fin.chunks_stored << "\n";

        const fs::path dst = tmp / "file.bin.downloaded";
        client.file_get_public(file_fin.data_map_address, dst.string());
        if (read_file(dst) != file_content) {
            std::cerr << "file round-trip mismatch\n";
            return 1;
        }
        std::cout << "File round-trip OK!\n";

        // --- 2. single-chunk publish via external signer ------------------
        std::string chunk_text;
        for (int i = 0; i < 8; ++i) chunk_text += "hello external signer from c++ (chunk)\n";
        std::vector<uint8_t> chunk_data(chunk_text.begin(), chunk_text.end());

        auto chunk_prep = client.prepare_chunk_upload(chunk_data);
        if (chunk_prep.already_stored) {
            std::cout << "Chunk prepare: already_stored, address=" << chunk_prep.address << "\n";
        } else {
            std::cout << "Chunk prepare: upload_id=" << chunk_prep.upload_id.substr(0, 16)
                      << "..., address=" << chunk_prep.address
                      << ", payments=" << chunk_prep.payments.size()
                      << ", total_amount=" << chunk_prep.total_amount << "\n";
            auto chunk_tx_hashes = external_signer_pay(
                chunk_prep.rpc_url, chunk_prep.payment_vault_address,
                chunk_prep.payment_token_address, chunk_prep.payments);
            auto addr = client.finalize_chunk_upload(chunk_prep.upload_id, chunk_tx_hashes);
            if (addr != chunk_prep.address) {
                std::cerr << "chunk address mismatch: " << addr << " != " << chunk_prep.address << "\n";
                return 1;
            }
            std::cout << "Chunk finalize: address=" << addr << "\n";
        }

        auto retrieved = client.chunk_get(chunk_prep.address);
        if (retrieved != chunk_data) {
            std::cerr << "chunk round-trip mismatch\n";
            return 1;
        }
        std::cout << "Chunk round-trip OK!\n";

        std::cout << "\n07-external-signer OK!\n";
    } catch (const antd::PartialUploadError& e) {
        // Payment settled, some chunks unstored. retryable == false means
        // retention is not confirmed: re-preparing pays only for the
        // remainder, but (over gRPC) a false from an unreadable message is
        // not proof the paid attempt was discarded, so don't treat it alone
        // as permission to pay again.
        std::cerr << "Partial upload (" << e.chunks_stored << "/" << e.total_chunks
                  << " stored, " << e.chunks_failed << " failed, retryable="
                  << (e.retryable ? "true" : "false") << "): " << e.what() << "\n";
        fs::remove_all(tmp);
        return 1;
    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        fs::remove_all(tmp);
        return 1;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        fs::remove_all(tmp);
        return 1;
    }
    fs::remove_all(tmp);
    return 0;
}
