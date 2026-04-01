#include <iostream>
#include "antd/antd.hpp"

int main() {
    try {
        antd::Client client;  // defaults to http://localhost:8082

        auto health = client.health();
        std::cout << "OK: " << (health.ok ? "true" : "false") << "\n";
        std::cout << "Network: " << health.network << "\n";
    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
