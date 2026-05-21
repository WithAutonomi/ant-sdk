#include <iostream>
#include <string>
#include <vector>
#include "antd/antd.hpp"

int main() {
    try {
        antd::Client client;

        // Store private (encrypted) data. The DataMap is returned to the
        // caller; it is NOT stored on-network.
        std::string secret = "Sensitive information";
        std::vector<uint8_t> data(secret.begin(), secret.end());

        auto result = client.data_put(data);
        std::cout << "Private data stored\n";
        std::cout << "Data map: " << result.data_map << "\n";
        std::cout << "Chunks: " << result.chunks_stored
                  << ", mode: " << result.payment_mode_used << "\n";

        // Retrieve using the caller-held DataMap.
        auto retrieved = client.data_get(result.data_map);
        std::string text(retrieved.begin(), retrieved.end());
        std::cout << "Retrieved: " << text << "\n";

    } catch (const antd::NotFoundError& e) {
        std::cerr << "Not found: " << e.what() << "\n";
        return 1;
    } catch (const antd::PaymentError& e) {
        std::cerr << "Payment failed: " << e.what() << "\n";
        return 1;
    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
