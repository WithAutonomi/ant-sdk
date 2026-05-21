#include <iostream>
#include <string>
#include <vector>
#include "antd/antd.hpp"

int main() {
    try {
        antd::Client client;

        // Store public data
        std::string msg = "Hello, Autonomi!";
        std::vector<uint8_t> data(msg.begin(), msg.end());

        auto result = client.data_put_public(data);
        std::cout << "Stored at: " << result.address << "\n";
        std::cout << "Chunks: " << result.chunks_stored
                  << ", mode: " << result.payment_mode_used << "\n";

        // Retrieve it
        auto retrieved = client.data_get_public(result.address);
        std::string text(retrieved.begin(), retrieved.end());
        std::cout << "Retrieved: " << text << "\n";

        // Estimate cost
        auto est = client.data_cost(data);
        std::cout << "Estimate: " << est.file_size << " bytes in " << est.chunk_count
                  << " chunks, storage " << est.cost << " atto, gas "
                  << est.estimated_gas_cost_wei << " wei, mode " << est.payment_mode << "\n";

    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
