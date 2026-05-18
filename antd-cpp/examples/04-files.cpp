#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include "antd/antd.hpp"

namespace fs = std::filesystem;

static std::string read_file(const fs::path& path) {
    std::ifstream f(path);
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

static void write_file(const fs::path& path, const std::string& content) {
    std::ofstream f(path);
    f << content;
}

int main() {
    fs::path tmp = fs::temp_directory_path() / "antd-cpp-04-files";
    std::error_code ec;
    fs::remove_all(tmp, ec);
    fs::create_directories(tmp);

    const std::string file_content = "Hello from a file on Autonomi!";

    fs::path src_file = tmp / "hello.txt";
    write_file(src_file, file_content);

    try {
        antd::Client client;

        auto est = client.file_cost(src_file.string(), true);
        std::cout << "Estimate: " << est.file_size << " bytes in " << est.chunk_count
                  << " chunks, storage " << est.cost << " atto, gas "
                  << est.estimated_gas_cost_wei << " wei, mode " << est.payment_mode << "\n";

        auto result = client.file_upload_public(src_file.string());
        std::cout << "File uploaded at: " << result.address << "\n";
        std::cout << "  storage: " << result.storage_cost_atto << " atto, gas: "
                  << result.gas_cost_wei << " wei\n";
        std::cout << "  chunks: " << result.chunks_stored << ", mode: "
                  << result.payment_mode_used << "\n";

        fs::path dst_file = tmp / "hello.txt.downloaded";
        client.file_download_public(result.address, dst_file.string());
        std::cout << "File downloaded to " << dst_file << "\n";

        std::string got = read_file(dst_file);
        if (got != file_content) {
            std::cerr << "Round-trip mismatch: wrote " << file_content.size()
                      << " bytes, read " << got.size() << " bytes\n";
            return 1;
        }

        std::cout << "File upload/download OK!\n";
    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        fs::remove_all(tmp, ec);
        return 1;
    }

    fs::remove_all(tmp, ec);
    return 0;
}
