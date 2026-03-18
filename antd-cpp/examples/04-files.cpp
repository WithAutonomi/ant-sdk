#include <iostream>
#include "antd/antd.hpp"

int main() {
    try {
        antd::Client client;

        // Upload a file
        auto result = client.file_upload_public("/tmp/example.txt");
        std::cout << "File uploaded at: " << result.address << "\n";
        std::cout << "Cost: " << result.cost << " atto\n";

        // Download it
        client.file_download_public(result.address, "/tmp/downloaded.txt");
        std::cout << "File downloaded to /tmp/downloaded.txt\n";

        // Upload a directory
        auto dir_result = client.dir_upload_public("/tmp/mydir");
        std::cout << "Directory uploaded at: " << dir_result.address << "\n";

        // Download directory
        client.dir_download_public(dir_result.address, "/tmp/mydir-copy");
        std::cout << "Directory downloaded to /tmp/mydir-copy\n";

        // Estimate file upload cost
        auto cost = client.file_cost("/tmp/example.txt", true, false);
        std::cout << "Estimated file cost: " << cost << " atto\n";

    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
