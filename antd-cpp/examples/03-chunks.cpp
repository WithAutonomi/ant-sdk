#include <iostream>
#include <string>
#include <vector>
#include "antd/antd.hpp"

int main() {
    try {
        antd::Client client;

        // Store a raw chunk
        std::string raw = "raw chunk payload";
        std::vector<uint8_t> data(raw.begin(), raw.end());

        auto result = client.chunk_put(data);
        std::cout << "Chunk stored at: " << result.address << "\n";
        std::cout << "Cost: " << result.cost << " atto\n";

        // Retrieve the chunk
        auto chunk = client.chunk_get(result.address);
        std::string text(chunk.begin(), chunk.end());
        std::cout << "Retrieved chunk: " << text << "\n";

    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
