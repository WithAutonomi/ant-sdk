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
        std::cout << "Cost: " << result.cost << " atto\n";

        // Retrieve it
        auto retrieved = client.data_get_public(result.address);
        std::string text(retrieved.begin(), retrieved.end());
        std::cout << "Retrieved: " << text << "\n";

        // Estimate cost
        auto cost = client.data_cost(data);
        std::cout << "Estimated cost: " << cost << " atto\n";

    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
