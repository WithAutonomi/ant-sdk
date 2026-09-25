// ---------------------------------------------------------------------------
// Tests for examples/external_signer_util.hpp, the support code of
// examples/07-external-signer.cpp:
//
//   1. run_capture starts a program without a shell: shell metacharacters in
//      its arguments reach the program literally and are never executed
//      (POSIX only; the Windows runner cannot run here).
//   2. The Windows command-line quoting round-trips hostile arguments through
//      the MSVC argument-parsing rules (platform-independent logic).
//   3. The validators for the daemon-provided payment fields.
// ---------------------------------------------------------------------------

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "external_signer_util.hpp"

#include <filesystem>
#include <stdexcept>
#include <string>
#include <vector>

#ifndef _WIN32
#include <unistd.h>
#endif

namespace ex = antd_example;

namespace {

// Reference parser for the arguments after the program name on a Windows
// command line, following Microsoft's documented rules ("Parsing C++
// command-line arguments"), which the MSVC runtime and CommandLineToArgvW
// apply. Anchored by the documented examples in the first test below.
std::vector<std::string> parse_windows_args(const std::string& s) {
    std::vector<std::string> out;
    std::size_t i = 0;
    const std::size_t n = s.size();
    for (;;) {
        while (i < n && (s[i] == ' ' || s[i] == '\t')) ++i;
        if (i >= n) break;
        std::string arg;
        bool quoted = false;
        while (i < n) {
            const char c = s[i];
            if (!quoted && (c == ' ' || c == '\t')) break;
            if (c == '\\') {
                std::size_t k = 0;
                while (i < n && s[i] == '\\') {
                    ++k;
                    ++i;
                }
                if (i < n && s[i] == '"') {
                    arg.append(k / 2, '\\');
                    if (k % 2 == 1) {  // odd: an escaped, literal quote
                        arg.push_back('"');
                        ++i;
                    }                  // even: the quote is a delimiter
                } else {
                    arg.append(k, '\\');
                }
                continue;
            }
            if (c == '"') {
                if (quoted && i + 1 < n && s[i + 1] == '"') {  // "" inside quotes
                    arg.push_back('"');
                    i += 2;
                } else {
                    quoted = !quoted;
                    ++i;
                }
                continue;
            }
            arg.push_back(c);
            ++i;
        }
        out.push_back(arg);
    }
    return out;
}

// Arguments a shell would act on, plus the reviewer's substitution probe.
std::vector<std::string> hostile_args() {
    return {
        "https://rpc.invalid/$(printf HERMES_SUBSTITUTED)",
        "$(printf X)",
        "`printf X`",
        "a; printf X",
        "a && printf X",
        "a || printf X",
        "a | printf X",
        "'single quoted'",
        "\"double quoted\"",
        "say \"hi\" twice",
        "two  spaces",
        "tab\there",
        "$HOME ${HOME} %PATH% !x",
        "* ? [a]",
        "> redirected < in",
        "^&<>|()",
        "a\\b",
        "trailing\\",
        "trailing space\\",
        "a\\\"b",
        "",
        "\xc3\xa9t\xc3\xa9",  // UTF-8
    };
}

}  // namespace

// ---------------------------------------------------------------------------
// Windows command-line quoting (logic only; runs on every platform)
// ---------------------------------------------------------------------------

TEST_CASE("reference parser matches Microsoft's documented examples") {
    using V = std::vector<std::string>;
    CHECK(parse_windows_args(R"("a b c" d e)") == V{"a b c", "d", "e"});
    CHECK(parse_windows_args(R"("ab\"c" "\\" d)") == V{"ab\"c", "\\", "d"});
    CHECK(parse_windows_args(R"(a\\\b d"e f"g h)") == V{"a\\\\\\b", "de fg", "h"});
    CHECK(parse_windows_args(R"(a\\\"b c d)") == V{"a\\\"b", "c", "d"});
    CHECK(parse_windows_args(R"(a\\\\"b c" d e)") == V{"a\\\\b c", "d", "e"});
    CHECK(parse_windows_args(R"(a"b"" c d)") == V{"ab\" c d"});
}

TEST_CASE("quote_windows_arg quotes only when needed and escapes quotes and trailing backslashes") {
    CHECK(ex::quote_windows_arg("plain") == "plain");
    CHECK(ex::quote_windows_arg("a\\b") == "a\\b");
    CHECK(ex::quote_windows_arg("$(printf X)") == "\"$(printf X)\"");
    CHECK(ex::quote_windows_arg("") == "\"\"");
    CHECK(ex::quote_windows_arg("two words") == "\"two words\"");
    CHECK(ex::quote_windows_arg("a\"b") == "\"a\\\"b\"");
    CHECK(ex::quote_windows_arg("a\\\"b") == "\"a\\\\\\\"b\"");
    CHECK(ex::quote_windows_arg("trailing space\\") == "\"trailing space\\\\\"");
}

TEST_CASE("windows_command_line round-trips hostile arguments through the MSVC parsing rules") {
    const auto args = hostile_args();
    std::vector<std::string> argv{"cast"};
    argv.insert(argv.end(), args.begin(), args.end());
    const std::string line = ex::windows_command_line(argv);
    REQUIRE(line.rfind("\"cast\" ", 0) == 0);
    CHECK(parse_windows_args(line.substr(7)) == args);
}

TEST_CASE("windows_command_line rejects what it cannot pass through unchanged") {
    CHECK_THROWS_AS(ex::windows_command_line({}), std::invalid_argument);
    CHECK_THROWS_AS(ex::windows_command_line({"ca\"st"}), std::invalid_argument);
    // Extra parentheses: the braced list's comma would split the macro.
    CHECK_THROWS_AS((ex::windows_command_line({"cast", std::string("a\0b", 3)})),
                    std::invalid_argument);
}

// ---------------------------------------------------------------------------
// run_capture: no shell (POSIX)
// ---------------------------------------------------------------------------

#ifndef _WIN32

TEST_CASE("run_capture passes shell metacharacters literally and never executes them") {
    // Canary: if any argument were evaluated by a shell, this file would be
    // created.
    const std::string canary = (std::filesystem::temp_directory_path() /
                                ("antd_cpp_injection_canary_" + std::to_string(::getpid())))
                                   .string();
    std::filesystem::remove(canary);

    auto args = hostile_args();
    args.push_back("$(touch " + canary + ")");
    args.push_back("`touch " + canary + "`");
    args.push_back("; touch " + canary);
    args.push_back("&& touch " + canary);

    // printf reuses its format for every operand and prints %s operands
    // verbatim, so the output is each argument on its own line.
    std::vector<std::string> argv{"printf", "%s\n"};
    argv.insert(argv.end(), args.begin(), args.end());
    std::string expected;
    for (const auto& a : args) expected += a + "\n";

    CHECK(ex::run_capture(argv) == expected);
    CHECK_FALSE(std::filesystem::exists(canary));
}

TEST_CASE("run_capture returns output larger than the pipe buffer intact") {
    const std::string big(100000, 'x');  // above the 64 KiB pipe buffer
    CHECK(ex::run_capture({"printf", "%s", big}) == big);
}

TEST_CASE("run_capture reports failures by program name only") {
    try {
        ex::run_capture({"false", "SECRET-ARGUMENT"});
        FAIL("a non-zero exit must throw");
    } catch (const std::runtime_error& e) {
        const std::string what = e.what();
        CHECK(what.find("false") != std::string::npos);
        CHECK(what.find("status 1") != std::string::npos);
        CHECK(what.find("SECRET-ARGUMENT") == std::string::npos);
    }
    CHECK_THROWS_AS(ex::run_capture({"antd-cpp-no-such-program-4d1c"}), std::runtime_error);
    CHECK_THROWS_AS(ex::run_capture({}), std::invalid_argument);
    CHECK_THROWS_AS((ex::run_capture({"printf", std::string("a\0b", 3)})),
                    std::invalid_argument);
}

#endif  // !_WIN32

// ---------------------------------------------------------------------------
// Daemon-provided payment field validation
// ---------------------------------------------------------------------------

namespace {

const std::string kAddr = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
const std::string kHash = "a3f1c2d4e5b6978812345678901234567890abcdefABCDEF0123456789abcdef";
const std::string kUint256Max =
    "115792089237316195423570985008687907853269984665640564039457584007913129639935";

}  // namespace

TEST_CASE("is_evm_address accepts 0x + 40 hex only") {
    CHECK(ex::is_evm_address(kAddr));
    CHECK(ex::is_evm_address("0x0000000000000000000000000000000000000000"));
    CHECK_FALSE(ex::is_evm_address(""));
    CHECK_FALSE(ex::is_evm_address(kAddr.substr(2)));            // no prefix
    CHECK_FALSE(ex::is_evm_address("0X" + kAddr.substr(2)));     // uppercase prefix
    CHECK_FALSE(ex::is_evm_address(kAddr.substr(0, 41)));        // 39 hex
    CHECK_FALSE(ex::is_evm_address(kAddr + "a"));                // 41 hex
    CHECK_FALSE(ex::is_evm_address("0x5FbDB2315678afecb367f032d93F642f64180aaG"));
    CHECK_FALSE(ex::is_evm_address(" " + kAddr));
    CHECK_FALSE(ex::is_evm_address(kAddr + "\n"));
    CHECK_FALSE(ex::is_evm_address("--private-key"));
    CHECK_FALSE(ex::is_evm_address("0x$(printf HERMES_SUBSTITUTED)0000000000000000000"));
}

TEST_CASE("is_bytes32_hex accepts 64 hex with or without 0x") {
    CHECK(ex::is_bytes32_hex(kHash));
    CHECK(ex::is_bytes32_hex("0x" + kHash));
    CHECK_FALSE(ex::is_bytes32_hex(""));
    CHECK_FALSE(ex::is_bytes32_hex("0x"));
    CHECK_FALSE(ex::is_bytes32_hex(kHash.substr(1)));  // 63
    CHECK_FALSE(ex::is_bytes32_hex(kHash + "0"));      // 65
    CHECK_FALSE(ex::is_bytes32_hex("0x0x" + kHash.substr(2)));
    CHECK_FALSE(ex::is_bytes32_hex(kHash.substr(0, 63) + "g"));
    CHECK_FALSE(ex::is_bytes32_hex(kHash.substr(0, 63) + ";"));
}

TEST_CASE("is_decimal_uint256 accepts plain decimals in uint256 range") {
    CHECK(ex::is_decimal_uint256("0"));
    CHECK(ex::is_decimal_uint256("1"));
    CHECK(ex::is_decimal_uint256("1000000000000000000"));
    CHECK(ex::is_decimal_uint256(kUint256Max));
    CHECK_FALSE(ex::is_decimal_uint256(""));
    CHECK_FALSE(ex::is_decimal_uint256("-1"));
    CHECK_FALSE(ex::is_decimal_uint256("+1"));
    CHECK_FALSE(ex::is_decimal_uint256("1.5"));
    CHECK_FALSE(ex::is_decimal_uint256("1e18"));
    CHECK_FALSE(ex::is_decimal_uint256("0x10"));
    CHECK_FALSE(ex::is_decimal_uint256("12 34"));
    CHECK_FALSE(ex::is_decimal_uint256("1;2"));
    CHECK_FALSE(ex::is_decimal_uint256(kUint256Max.substr(0, 77) + "6"));  // 2^256
    CHECK_FALSE(ex::is_decimal_uint256(kUint256Max + "0"));                // 79 digits
}

TEST_CASE("is_http_url accepts http(s) URLs of printable ASCII only") {
    CHECK(ex::is_http_url("http://127.0.0.1:8545"));
    CHECK(ex::is_http_url("https://rpc.example.org/v1?key=abc&x=1"));
    CHECK_FALSE(ex::is_http_url(""));
    CHECK_FALSE(ex::is_http_url("http://"));
    CHECK_FALSE(ex::is_http_url("ftp://rpc.example.org"));
    CHECK_FALSE(ex::is_http_url("file:///etc/passwd"));
    CHECK_FALSE(ex::is_http_url("HTTP://rpc.example.org"));
    CHECK_FALSE(ex::is_http_url("--rpc-url=http://x"));
    CHECK_FALSE(ex::is_http_url(" http://127.0.0.1:8545"));
    CHECK_FALSE(ex::is_http_url("https://rpc.invalid/$(printf HERMES_SUBSTITUTED)"));  // space
    CHECK_FALSE(ex::is_http_url("http://a\tb"));
    CHECK_FALSE(ex::is_http_url("http://a\nb"));
    CHECK_FALSE(ex::is_http_url(std::string("http://a\0b", 10)));
    CHECK_FALSE(ex::is_http_url("http://a\x7f"));
    CHECK_FALSE(ex::is_http_url("http://\xc3\xa9"));
    CHECK_FALSE(ex::is_http_url("http://" + std::string(2042, 'a')));  // 2049 bytes
}

TEST_CASE("validate_signing_request accepts a well-formed response and names the first bad field") {
    const std::string rpc = "http://127.0.0.1:8545";
    const std::vector<antd::PaymentInfo> good{{kHash, kAddr, "1000"}, {"0x" + kHash, kAddr, "0"}};
    CHECK_NOTHROW(ex::validate_signing_request(rpc, kAddr, kAddr, good));
    CHECK_NOTHROW(ex::validate_signing_request(rpc, kAddr, kAddr, {}));

    const auto rejects = [&](const std::string& url, const std::string& vault,
                             const std::string& token,
                             const std::vector<antd::PaymentInfo>& payments,
                             const std::string& field) {
        CAPTURE(field);
        try {
            ex::validate_signing_request(url, vault, token, payments);
            FAIL("should have thrown");
        } catch (const std::invalid_argument& e) {
            CHECK(std::string(e.what()).find(field) != std::string::npos);
        }
    };
    rejects("https://rpc.invalid/$(printf HERMES_SUBSTITUTED)", kAddr, kAddr, good, "rpc_url");
    rejects(rpc, "0xnot-an-address", kAddr, good, "payment_vault_address");
    rejects(rpc, kAddr, "", good, "payment_token_address");
    rejects(rpc, kAddr, kAddr, {{kHash, "0x1234", "1"}}, "payments[0].rewards_address");
    rejects(rpc, kAddr, kAddr, {{kHash, kAddr, "1"}, {kHash, kAddr, "1; rm -rf /"}},
            "payments[1].amount");
    rejects(rpc, kAddr, kAddr, {{"$(printf X)", kAddr, "1"}}, "payments[0].quote_hash");
}
