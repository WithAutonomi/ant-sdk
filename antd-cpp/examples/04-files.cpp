#include <iostream>
#include "antd/antd.hpp"

int main() {
    try {
        antd::Client client;

        // Upload a file
        auto result = client.file_upload_public("/tmp/example.txt");
        std::cout << "File uploaded at: " << result.address << "\n";
        std::cout << "  storage: " << result.storage_cost_atto << " atto, gas: "
                  << result.gas_cost_wei << " wei\n";
        std::cout << "  chunks: " << result.chunks_stored << ", mode: "
                  << result.payment_mode_used << "\n";

        // Download it
        client.file_download_public(result.address, "/tmp/downloaded.txt");
        std::cout << "File downloaded to /tmp/downloaded.txt\n";

        // Estimate file upload cost
        auto est = client.file_cost("/tmp/example.txt", true);
        std::cout << "Estimate: " << est.file_size << " bytes in " << est.chunk_count
                  << " chunks, storage " << est.cost << " atto, gas "
                  << est.estimated_gas_cost_wei << " wei, mode " << est.payment_mode << "\n";

    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
