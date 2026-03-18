#include <iostream>
#include <string>
#include <vector>
#include "antd/antd.hpp"

int main() {
    try {
        antd::Client client;

        // Store private (encrypted) data
        std::string secret = "Sensitive information";
        std::vector<uint8_t> data(secret.begin(), secret.end());

        auto result = client.data_put_private(data);
        std::cout << "Private data stored\n";
        std::cout << "Data map: " << result.address << "\n";
        std::cout << "Cost: " << result.cost << " atto\n";

        // Retrieve using the data map
        auto retrieved = client.data_get_private(result.address);
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
