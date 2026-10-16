// Example 09: Manifests — one `.ant` file or `ant://` link for a set of files.
//
// Uploads two small pieces of public data, builds a manifest that names them
// `notes/one.txt` and `notes/two.txt`, prints its link and entries, then
// decodes the link with `resolve` to print each file's exact size.
//
//   ANTD_BASE_URL  optional; the daemon's REST URL (default
//                  http://localhost:8082)
//
// The two uploads are paid. Building and decoding the manifest upload and pay
// for nothing: the daemon only reads the network to resolve DataMaps.

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include "antd/antd.hpp"

namespace {

std::vector<uint8_t> bytes(const std::string& s) { return {s.begin(), s.end()}; }

}  // namespace

int main() {
    const char* url_env = std::getenv("ANTD_BASE_URL");

    try {
        antd::Client client(url_env != nullptr && *url_env != '\0' ? url_env
                                                                     : antd::kDefaultBaseURL);

        // 1. Two pieces of public data for the manifest to describe (paid).
        const auto one = client.data_put_public(bytes("The first note in the manifest."));
        const auto two = client.data_put_public(bytes("The second note, a little longer than the first."));
        std::cout << "Stored notes/one.txt at " << one.address << "\n";
        std::cout << "Stored notes/two.txt at " << two.address << "\n";

        // 2. Build a manifest of them (free). The default options embed
        //    resolved roots; public entries are referenced by address.
        antd::BuildManifestOptions opts;
        opts.name = "example";
        const auto built = client.build_manifest(
            {
                {.path = "notes/one.txt", .address = one.address},
                {.path = "notes/two.txt", .address = two.address},
            },
            opts);

        std::cout << "Manifest: " << built.manifest.size() << " bytes\n";
        if (built.link.empty()) {
            std::cout << "Link: (too long for a link; share the .ant bytes)\n";
        } else {
            std::cout << "Link: " << built.link << "\n";
        }
        for (const auto& e : built.entries) {
            std::cout << "  " << e.effective_name << " -> " << e.content_address << " ("
                      << e.kind << ")\n";
        }

        // 3. Decode it with resolve: the daemon fetches each entry's DataMap
        //    to report its exact size. A failure is reported per entry.
        const auto decoded = built.link.empty() ? client.decode_manifest(built.manifest, true)
                                                : client.decode_manifest_link(built.link, true);
        std::cout << "Decoded " << decoded.source;
        if (decoded.name) std::cout << " \"" << *decoded.name << "\"";
        std::cout << ":\n";
        for (const auto& e : decoded.entries) {
            std::cout << "  " << e.effective_name << ": ";
            if (e.exact_size) {
                std::cout << *e.exact_size << " bytes\n";
            } else {
                std::cout << "size unknown (" << (e.error.empty() ? "not resolved" : e.error)
                          << ")\n";
            }
        }
    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
