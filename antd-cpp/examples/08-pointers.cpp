// Example 08: Pointers — a mutable, owner-signed reference to public data.
//
// Uploads two small pieces of public data, creates a pointer at the first,
// updates it to the second, reads it back and prints where its close group
// says it stands.
//
// The daemon signs pointer writes with owner keys it loaded at startup
// (`antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`),
// so the pointer is named by its address. Set:
//
//   ANTD_POINTER_OWNER  a pointer address the daemon holds a key for
//                       (Client::pointer_keys lists them)
//   ANTD_BASE_URL       optional; the daemon's REST URL (default
//                       http://localhost:8082)
//
// Every write pays (about the price of one chunk), and every attempt pays
// again, so this example never retries a write.

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include "antd/antd.hpp"

namespace {

const char* status_name(antd::PointerFinalityStatus s) {
    switch (s) {
        case antd::PointerFinalityStatus::Open:        return "open";
        case antd::PointerFinalityStatus::Settling:    return "settling";
        case antd::PointerFinalityStatus::Unconfirmed: return "unconfirmed";
        case antd::PointerFinalityStatus::Final:       return "final";
        case antd::PointerFinalityStatus::Forked:      return "forked";
        case antd::PointerFinalityStatus::Unknown:     break;
    }
    return "unknown";
}

std::vector<uint8_t> bytes(const std::string& s) { return {s.begin(), s.end()}; }

}  // namespace

int main() {
    const char* owner_env = std::getenv("ANTD_POINTER_OWNER");
    if (owner_env == nullptr || *owner_env == '\0') {
        std::cerr << "Set ANTD_POINTER_OWNER to a pointer address the daemon holds a key for\n";
        return 2;
    }
    const std::string owner = owner_env;
    const char* url_env = std::getenv("ANTD_BASE_URL");

    try {
        antd::Client client(url_env != nullptr && *url_env != '\0' ? url_env
                                                                     : antd::kDefaultBaseURL);

        // 1. Two pieces of public data for the pointer to point at.
        const auto first = client.data_put_public(bytes("pointer target, version 1"));
        const auto second = client.data_put_public(bytes("pointer target, version 2"));
        std::cout << "Stored v1 at " << first.address << "\n";
        std::cout << "Stored v2 at " << second.address << "\n";

        // 2. Create the pointer at the first. A pointer that already exists
        //    is refused before anything is paid; the update below moves it.
        try {
            const auto created = client.pointer_create(owner, first.address);
            std::cout << "Created pointer " << created.address << " (counter "
                      << created.counter << ")\n";
        } catch (const antd::AlreadyExistsError&) {
            std::cout << "Pointer " << owner << " already exists; updating it\n";
        }

        // 3. Point it at the second.
        const auto updated = client.pointer_update(owner, second.address);
        std::cout << "Updated pointer to v2 (counter " << updated.counter << ")\n";

        // 4. Read it back, and follow it to the data.
        const auto record = client.pointer_get(owner);
        std::cout << "Pointer " << record.address << " -> " << record.target << " ("
                  << record.kind << ", counter " << record.counter
                  << (record.is_final ? ", final" : "") << ")\n";
        const auto resolved = client.pointer_resolve(owner);
        const auto data = client.data_get_public(resolved.target);
        std::cout << "Resolves to " << resolved.target << ": "
                  << std::string(data.begin(), data.end()) << "\n";

        // 5. Where the whole close group says it stands.
        const auto finality = client.pointer_finality(owner);
        std::cout << "Finality: " << status_name(finality.status) << " ("
                  << finality.answered << "/" << finality.group << " peers answered";
        if (finality.counter) {
            std::cout << ", counter " << *finality.counter;
        }
        std::cout << ")\n";
    } catch (const antd::PointerFinalError& e) {
        std::cerr << "Pointer is final (transferred or frozen): " << e.what() << "\n";
        return 1;
    } catch (const antd::AntdError& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
