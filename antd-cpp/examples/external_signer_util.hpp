// Support code for examples/07-external-signer.cpp: start `cast` without a
// shell, and validate the daemon-provided payment fields before any of them
// becomes a `cast` argument.
//
// Header-only and used only by that example and its test
// (tests/test_external_signer_util.cpp); not part of the antd library.
#pragma once

#include <cstddef>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

#include "antd/models.hpp"

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <filesystem>
#else
#include <cerrno>
#include <fcntl.h>
#include <spawn.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;
#endif

namespace antd_example {

// ---------------------------------------------------------------------------
// Validation of the daemon-provided payment fields
//
// The prepare response arrives over the network. Every field that becomes a
// `cast` argument must have its exact expected shape before any process
// starts, so a malformed or hostile value is rejected up front and can never
// pass for a `cast` flag.
// ---------------------------------------------------------------------------

inline bool is_hex_digits(std::string_view s, std::size_t count) {
    if (s.size() != count) return false;
    for (const char c : s) {
        const bool hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
                         (c >= 'A' && c <= 'F');
        if (!hex) return false;
    }
    return true;
}

/// `0x` followed by exactly 40 hex digits: a 20-byte EVM address.
inline bool is_evm_address(std::string_view s) {
    return s.size() == 42 && s.substr(0, 2) == "0x" && is_hex_digits(s.substr(2), 40);
}

/// Exactly 64 hex digits, with or without a `0x` prefix: a bytes32 such as a
/// quote hash or a transaction hash.
inline bool is_bytes32_hex(std::string_view s) {
    if (s.substr(0, 2) == "0x") s.remove_prefix(2);
    return is_hex_digits(s, 64);
}

/// A plain decimal integer in uint256 range (0 to 2^256 - 1): ASCII digits
/// only, no sign, no exponent, no hex.
inline bool is_decimal_uint256(std::string_view s) {
    constexpr std::string_view kMax =
        "115792089237316195423570985008687907853269984665640564039457584007913129639935";
    if (s.empty() || s.size() > kMax.size()) return false;
    for (const char c : s) {
        if (c < '0' || c > '9') return false;
    }
    return s.size() < kMax.size() || s <= kMax;
}

/// An `http://` or `https://` URL with a non-empty remainder, at most 2048
/// bytes, of printable ASCII only: no whitespace and no control characters.
inline bool is_http_url(std::string_view s) {
    std::size_t scheme = 0;
    if (s.substr(0, 7) == "http://") {
        scheme = 7;
    } else if (s.substr(0, 8) == "https://") {
        scheme = 8;
    } else {
        return false;
    }
    if (s.size() == scheme || s.size() > 2048) return false;
    for (const char c : s) {
        const auto u = static_cast<unsigned char>(c);
        if (u <= 0x20 || u >= 0x7f) return false;
    }
    return true;
}

/// Check every daemon-provided field that the example passes to `cast`.
/// Throws std::invalid_argument naming the first bad field. The value is not
/// echoed, since it may hold control characters.
inline void validate_signing_request(const std::string& rpc_url,
                                     const std::string& payment_vault_address,
                                     const std::string& payment_token_address,
                                     const std::vector<antd::PaymentInfo>& payments) {
    const auto require = [](bool ok, const std::string& what) {
        if (!ok) throw std::invalid_argument("invalid daemon prepare response: " + what);
    };
    require(is_http_url(rpc_url),
            "rpc_url is not an http(s) URL of printable ASCII (no whitespace or control characters)");
    require(is_evm_address(payment_vault_address),
            "payment_vault_address is not 0x followed by 40 hex digits");
    require(is_evm_address(payment_token_address),
            "payment_token_address is not 0x followed by 40 hex digits");
    for (std::size_t i = 0; i < payments.size(); ++i) {
        const auto& p = payments[i];
        const std::string at = "payments[" + std::to_string(i) + "].";
        require(is_evm_address(p.rewards_address),
                at + "rewards_address is not 0x followed by 40 hex digits");
        require(is_decimal_uint256(p.amount), at + "amount is not a decimal uint256");
        require(is_bytes32_hex(p.quote_hash), at + "quote_hash is not 64 hex digits");
    }
}

// ---------------------------------------------------------------------------
// Shell-free process execution
// ---------------------------------------------------------------------------

/// Reject an argument vector that cannot be passed through unchanged: no
/// program, or an embedded NUL (which would silently truncate an argument).
inline void check_argv(const std::vector<std::string>& argv) {
    if (argv.empty() || argv[0].empty()) {
        throw std::invalid_argument("run_capture: no program given");
    }
    for (const auto& a : argv) {
        if (a.find('\0') != std::string::npos) {
            throw std::invalid_argument("run_capture: an argument contains a NUL byte");
        }
    }
}

/// Quote one argument for a Windows command line so that the MSVC runtime's
/// argument parser (and CommandLineToArgvW) reads back exactly `arg`: wrap it
/// in double quotes when it is empty or holds whitespace or a quote, escape
/// each embedded quote with a backslash, and double any run of backslashes
/// that precedes a quote or the closing quote. Backslashes elsewhere are
/// literal. Defined on every platform so the quoting can be tested anywhere.
inline std::string quote_windows_arg(const std::string& arg) {
    if (!arg.empty() && arg.find_first_of(" \t\n\v\"") == std::string::npos) {
        return arg;
    }
    std::string out = "\"";
    for (std::size_t i = 0;; ++i) {
        std::size_t backslashes = 0;
        while (i < arg.size() && arg[i] == '\\') {
            ++backslashes;
            ++i;
        }
        if (i == arg.size()) {
            out.append(backslashes * 2, '\\');
            break;
        }
        if (arg[i] == '"') {
            out.append(backslashes * 2 + 1, '\\');
        } else {
            out.append(backslashes, '\\');
        }
        out.push_back(arg[i]);
    }
    out.push_back('"');
    return out;
}

/// The full Windows command line for `argv`. The program name follows its
/// own rule (quotes delimit it, backslashes are literal), so it is always
/// quoted and may not itself contain a double quote.
inline std::string windows_command_line(const std::vector<std::string>& argv) {
    check_argv(argv);
    if (argv[0].find('"') != std::string::npos) {
        throw std::invalid_argument("run_capture: program name contains a double quote");
    }
    std::string line = "\"" + argv[0] + "\"";
    for (std::size_t i = 1; i < argv.size(); ++i) {
        line += ' ';
        line += quote_windows_arg(argv[i]);
    }
    return line;
}

#ifdef _WIN32
namespace detail {

inline std::wstring widen(const std::string& s) {
    if (s.empty()) return std::wstring();
    const int n = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(),
                                        static_cast<int>(s.size()), nullptr, 0);
    if (n <= 0) throw std::invalid_argument("run_capture: an argument is not valid UTF-8");
    std::wstring w(static_cast<std::size_t>(n), L'\0');
    ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), static_cast<int>(s.size()),
                          w.data(), n);
    return w;
}

/// Resolve `program` to an .exe path ourselves and hand CreateProcessW the
/// full path, so it neither searches the current directory first nor maps a
/// .bat / .cmd file onto cmd.exe.
inline std::filesystem::path resolve_program(const std::string& program) {
    namespace fs = std::filesystem;
    fs::path name(widen(program));
    if (!name.has_extension()) name += L".exe";
    std::wstring ext = name.extension().wstring();
    for (auto& c : ext) {
        if (c >= L'A' && c <= L'Z') c = static_cast<wchar_t>(c - L'A' + L'a');
    }
    if (ext != L".exe") {
        throw std::invalid_argument("run_capture: only .exe programs can be started without a shell");
    }
    if (name.has_parent_path()) return name;
    std::wstring path(32767, L'\0');
    const DWORD len = ::GetEnvironmentVariableW(L"PATH", path.data(),
                                                static_cast<DWORD>(path.size()));
    path.resize(len < path.size() ? len : 0);
    std::wstring_view rest(path);
    while (!rest.empty()) {
        const std::size_t semi = rest.find(L';');
        const std::wstring dir(rest.substr(0, semi));
        rest = semi == std::wstring_view::npos ? std::wstring_view() : rest.substr(semi + 1);
        if (dir.empty()) continue;
        std::error_code ec;
        const fs::path candidate = fs::path(dir) / name;
        if (fs::is_regular_file(candidate, ec)) return candidate;
    }
    throw std::runtime_error("cannot start " + program + ": not found on PATH");
}

inline std::string run_capture_windows(const std::vector<std::string>& argv) {
    const std::filesystem::path exe = resolve_program(argv[0]);
    std::wstring cmdline = widen(windows_command_line(argv));  // CreateProcessW may write to it

    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof sa;
    sa.bInheritHandle = TRUE;
    HANDLE read_end = nullptr;
    HANDLE write_end = nullptr;
    if (!::CreatePipe(&read_end, &write_end, &sa, 0)) {
        throw std::system_error(static_cast<int>(::GetLastError()), std::system_category(),
                                "CreatePipe");
    }
    // Only the write end goes to the child.
    ::SetHandleInformation(read_end, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOW si{};
    si.cb = sizeof si;
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = ::GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = write_end;
    si.hStdError = ::GetStdHandle(STD_ERROR_HANDLE);
    PROCESS_INFORMATION pi{};
    const BOOL started = ::CreateProcessW(exe.c_str(), cmdline.data(), nullptr, nullptr,
                                          TRUE, 0, nullptr, nullptr, &si, &pi);
    const DWORD start_error = started ? 0 : ::GetLastError();
    ::CloseHandle(write_end);
    if (!started) {
        ::CloseHandle(read_end);
        throw std::system_error(static_cast<int>(start_error), std::system_category(),
                                "cannot start " + argv[0]);
    }

    std::string out;
    char buf[4096];
    DWORD n = 0;
    while (::ReadFile(read_end, buf, sizeof buf, &n, nullptr) && n > 0) {
        out.append(buf, n);
    }
    ::CloseHandle(read_end);
    ::WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    ::GetExitCodeProcess(pi.hProcess, &code);
    ::CloseHandle(pi.hThread);
    ::CloseHandle(pi.hProcess);
    if (code != 0) {
        throw std::runtime_error(argv[0] + " exited with status " + std::to_string(code));
    }
    return out;
}

}  // namespace detail
#endif

/// Start argv[0] (looked up on PATH) with the arguments in `argv` and return
/// what it writes to stdout. No shell is involved on any platform, so every
/// argument reaches the program byte for byte, metacharacters included.
/// stdin and stderr are inherited.
///
/// POSIX: posix_spawnp plus a pipe for stdout, then waitpid. Windows:
/// CreateProcessW with an explicit .exe path and a command line quoted by
/// windows_command_line; never cmd.exe.
///
/// Throws if the program cannot start or exits non-zero. The error names
/// only the program, never the arguments (one of them is a private key).
inline std::string run_capture(const std::vector<std::string>& argv) {
    check_argv(argv);
#ifdef _WIN32
    return detail::run_capture_windows(argv);
#else
    int fds[2];
    if (::pipe(fds) != 0) {
        throw std::system_error(errno, std::generic_category(), "pipe");
    }
    // Close-on-exec on both ends so no other child inherits them; dup2 onto
    // the child's stdout below yields a descriptor without the flag.
    ::fcntl(fds[0], F_SETFD, FD_CLOEXEC);
    ::fcntl(fds[1], F_SETFD, FD_CLOEXEC);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO);
    std::vector<char*> cargv;
    cargv.reserve(argv.size() + 1);
    for (const auto& a : argv) cargv.push_back(const_cast<char*>(a.c_str()));
    cargv.push_back(nullptr);
    pid_t pid = 0;
    const int rc = ::posix_spawnp(&pid, cargv[0], &actions, nullptr, cargv.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    ::close(fds[1]);
    if (rc != 0) {
        ::close(fds[0]);
        throw std::system_error(rc, std::generic_category(), "cannot start " + argv[0]);
    }

    std::string out;
    char buf[4096];
    int read_error = 0;
    for (;;) {
        const ssize_t n = ::read(fds[0], buf, sizeof buf);
        if (n > 0) {
            out.append(buf, static_cast<std::size_t>(n));
        } else if (n == 0) {
            break;
        } else if (errno != EINTR) {
            read_error = errno;
            break;
        }
    }
    ::close(fds[0]);
    int status = 0;
    while (::waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) {
            throw std::system_error(errno, std::generic_category(), "waitpid " + argv[0]);
        }
    }
    if (read_error != 0) {
        throw std::system_error(read_error, std::generic_category(),
                                "reading the output of " + argv[0]);
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) return out;
    if (WIFEXITED(status)) {
        throw std::runtime_error(argv[0] + " exited with status " +
                                 std::to_string(WEXITSTATUS(status)));
    }
    throw std::runtime_error(argv[0] + " was terminated by signal " +
                             std::to_string(WTERMSIG(status)));
#endif
}

}  // namespace antd_example
