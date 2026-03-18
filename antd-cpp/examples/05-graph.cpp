#include <iostream>
#include <vector>
#include "antd/antd.hpp"

int main() {
    try {
        antd::Client client;

        // Create a graph entry (DAG node)
        auto result = client.graph_entry_put(
            "owner_secret_key_hex",
            {},  // no parents
            "content_hash_hex",
            {}   // no descendants
        );
        std::cout << "Graph entry created at: " << result.address << "\n";
        std::cout << "Cost: " << result.cost << " atto\n";

        // Read it back
        auto entry = client.graph_entry_get(result.address);
        std::cout << "Owner: " << entry.owner << "\n";
        std::cout << "Content: " << entry.content << "\n";
        std::cout << "Parents: " << entry.parents.size() << "\n";
        std::cout << "Descendants: " << entry.descendants.size() << "\n";

        // Check existence
        bool exists = client.graph_entry_exists(result.address);
        std::cout << "Exists: " << (exists ? "true" : "false") << "\n";

        // Estimate cost
        auto cost = client.graph_entry_cost("public_key_hex");
        std::cout << "Estimated cost: " << cost << " atto\n";

    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
