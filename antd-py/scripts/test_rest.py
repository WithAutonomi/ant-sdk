#!/usr/bin/env python
"""REST integration test for antd Python SDK.

Mirrors simple-test.ps1 — standalone script with colored pass/fail output.
Requires a running antd daemon on localhost:8080.

Usage: python scripts/test_rest.py
"""

import os
import sys
import time

# Add src to path for development
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from antd import AntdClient, AlreadyExistsError, PointerTarget

# --- Enable ANSI on Windows (same as C# TestRunner.EnableAnsi) ---

def _enable_ansi():
    if sys.platform != "win32":
        return True
    try:
        import ctypes
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.GetStdHandle(-11)  # STD_OUTPUT_HANDLE
        mode = ctypes.c_uint32()
        if kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            kernel32.SetConsoleMode(handle, mode.value | 0x0004)  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
            return True
    except Exception:
        pass
    return False

_enable_ansi()

# --- Colored output ---

GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
RESET = "\033[0m"
BOLD = "\033[1m"

results: list[tuple[str, str]] = []


def test_pass(name: str, detail: str = ""):
    results.append((name, "PASS"))
    print(f"  {GREEN}PASS{RESET}  {name}" + (f"  ({detail})" if detail else ""))


def test_fail(name: str, detail: str = ""):
    results.append((name, "FAIL"))
    print(f"  {RED}FAIL{RESET}  {name}" + (f"  ({detail})" if detail else ""))


def test_skip(name: str, detail: str = ""):
    results.append((name, "SKIP"))
    print(f"  {YELLOW}SKIP{RESET}  {name}" + (f"  ({detail})" if detail else ""))


# --- BLS keys (unique per data type to avoid DHT collisions) ---

KEY_POINTER = "0000000000000000000000000000000000000000000000000000000000000001"
KEY_SCRATCHPAD = "0000000000000000000000000000000000000000000000000000000000000002"
KEY_GRAPH = "0000000000000000000000000000000000000000000000000000000000000003"
KEY_REGISTER = "0000000000000000000000000000000000000000000000000000000000000004"

PROPAGATION_DELAY = 3  # seconds to wait for DHT propagation


def main():
    base_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080"
    print(f"\n{BOLD}{CYAN}antd Python SDK - REST Integration Test{RESET}")
    print(f"Target: {base_url}\n")

    client = AntdClient(base_url=base_url)

    # 1. Health check
    try:
        status = client.health()
        if status.ok:
            test_pass(f"Health check (network={status.network})")
        else:
            test_fail("Health check", "status != ok")
            print(f"\n{RED}Cannot reach antd daemon. Is it running?{RESET}")
            return 1
    except Exception as e:
        test_fail("Health check", str(e))
        print(f"\n{RED}Cannot reach antd daemon at {base_url}. Is it running?{RESET}")
        return 1

    # 2. Public data put/get round-trip
    data_addr = None
    try:
        test_data = b"hello from antd python SDK!"
        result = client.data_put_public(test_data)
        data_addr = result.address
        test_pass("Data put public", f"addr={result.address[:16]}... cost={result.cost}")
    except Exception as e:
        test_fail("Data put public", str(e))

    if data_addr:
        try:
            got = client.data_get_public(data_addr)
            if got == b"hello from antd python SDK!":
                test_pass("Data get public", f"{len(got)} bytes")
            else:
                test_fail("Data get public", f"data mismatch: got {len(got)} bytes")
        except Exception as e:
            test_fail("Data get public", str(e))
    else:
        test_skip("Data get public", "no address from put")

    # 3. Data cost estimation
    try:
        cost = client.data_cost(b"cost estimation test data")
        test_pass("Data cost", f"cost={cost}")
    except Exception as e:
        test_fail("Data cost", str(e))

    # 4. Chunk put/get round-trip
    chunk_addr = None
    try:
        chunk_data = b"chunk test payload from python"
        result = client.chunk_put(chunk_data)
        chunk_addr = result.address
        test_pass("Chunk put", f"addr={result.address[:16]}... cost={result.cost}")
    except Exception as e:
        test_fail("Chunk put", str(e))

    if chunk_addr:
        try:
            got = client.chunk_get(chunk_addr)
            if got == b"chunk test payload from python":
                test_pass("Chunk get", f"{len(got)} bytes")
            else:
                test_fail("Chunk get", "data mismatch")
        except Exception as e:
            test_fail("Chunk get", str(e))
    else:
        test_skip("Chunk get", "no address from put")

    # 5. Pointer create/exists/get/cost
    pointer_addr = None
    if chunk_addr:
        target = PointerTarget(kind="chunk", address=chunk_addr)
        try:
            result = client.pointer_create(KEY_POINTER, target)
            pointer_addr = result.address
            test_pass("Pointer create", f"addr={result.address[:16]}... cost={result.cost}")
        except AlreadyExistsError:
            # Expected on re-run. Derive the address from the public key.
            test_pass("Pointer create", "already exists (expected on re-run)")
            # We need the address, so get cost which tells us the key is valid
            pointer_addr = None
        except Exception as e:
            test_fail("Pointer create", str(e))

        if pointer_addr:
            print(f"  ... waiting {PROPAGATION_DELAY}s for DHT propagation")
            time.sleep(PROPAGATION_DELAY)

            try:
                exists = client.pointer_exists(pointer_addr)
                if exists:
                    test_pass("Pointer exists (HEAD)")
                else:
                    test_fail("Pointer exists (HEAD)", "returned False")
            except Exception as e:
                test_fail("Pointer exists (HEAD)", str(e))

            try:
                ptr = client.pointer_get(pointer_addr)
                if ptr.target.kind == "chunk" and ptr.target.address == chunk_addr:
                    test_pass("Pointer get", f"target={ptr.target.kind}:{ptr.target.address[:16]}...")
                else:
                    test_fail("Pointer get", f"unexpected target: {ptr.target}")
            except Exception as e:
                test_fail("Pointer get", str(e))

        if pointer_addr:
            try:
                cost = client.pointer_cost(pointer_addr)
                test_pass("Pointer cost", f"cost={cost}")
            except Exception as e:
                test_fail("Pointer cost", str(e))
        else:
            test_skip("Pointer cost", "no pointer address")
    else:
        test_skip("Pointer create", "no chunk address")
        test_skip("Pointer exists", "no pointer address")
        test_skip("Pointer get", "no pointer address")
        test_skip("Pointer cost", "no pointer address")

    # 6. Scratchpad create/exists/get/cost
    scratchpad_addr = None
    try:
        sp_data = b"scratchpad test data"
        result = client.scratchpad_create(KEY_SCRATCHPAD, 42, sp_data)
        scratchpad_addr = result.address
        test_pass("Scratchpad create", f"addr={result.address[:16]}... cost={result.cost}")
    except AlreadyExistsError:
        test_pass("Scratchpad create", "already exists (expected on re-run)")
    except Exception as e:
        test_fail("Scratchpad create", str(e))

    if scratchpad_addr:
        print(f"  ... waiting {PROPAGATION_DELAY}s for DHT propagation")
        time.sleep(PROPAGATION_DELAY)

        try:
            exists = client.scratchpad_exists(scratchpad_addr)
            if exists:
                test_pass("Scratchpad exists (HEAD)")
            else:
                test_fail("Scratchpad exists (HEAD)", "returned False")
        except Exception as e:
            test_fail("Scratchpad exists (HEAD)", str(e))

        try:
            sp = client.scratchpad_get(scratchpad_addr)
            test_pass("Scratchpad get", f"counter={sp.counter} encoding={sp.data_encoding}")
        except Exception as e:
            test_fail("Scratchpad get", str(e))

        try:
            cost = client.scratchpad_cost(scratchpad_addr)
            test_pass("Scratchpad cost", f"cost={cost}")
        except Exception as e:
            test_fail("Scratchpad cost", str(e))
    else:
        test_skip("Scratchpad exists", "no scratchpad address")
        test_skip("Scratchpad get", "no scratchpad address")
        test_skip("Scratchpad cost", "no scratchpad address")

    # 7. Graph entry put/exists/get/cost
    graph_addr = None
    try:
        content_hex = "ab" * 32  # 32 bytes as hex
        result = client.graph_entry_put(KEY_GRAPH, [], content_hex, [])
        graph_addr = result.address
        test_pass("Graph entry put", f"addr={result.address[:16]}... cost={result.cost}")
    except AlreadyExistsError:
        test_pass("Graph entry put", "already exists (expected on re-run)")
    except Exception as e:
        test_fail("Graph entry put", str(e))

    if graph_addr:
        print(f"  ... waiting {PROPAGATION_DELAY}s for DHT propagation")
        time.sleep(PROPAGATION_DELAY)

        try:
            exists = client.graph_entry_exists(graph_addr)
            if exists:
                test_pass("Graph entry exists (HEAD)")
            else:
                test_fail("Graph entry exists (HEAD)", "returned False")
        except Exception as e:
            test_fail("Graph entry exists (HEAD)", str(e))

        try:
            entry = client.graph_entry_get(graph_addr)
            test_pass("Graph entry get", f"owner={entry.owner[:16]}... content={entry.content[:16]}...")
        except Exception as e:
            test_fail("Graph entry get", str(e))

        try:
            cost = client.graph_entry_cost(graph_addr)
            test_pass("Graph entry cost", f"cost={cost}")
        except Exception as e:
            test_fail("Graph entry cost", str(e))
    else:
        test_skip("Graph entry exists", "no graph address")
        test_skip("Graph entry get", "no graph address")
        test_skip("Graph entry cost", "no graph address")

    # 8. Register create/get/cost
    register_addr = None
    try:
        initial_value = "cd" * 32  # 32 bytes as hex
        result = client.register_create(KEY_REGISTER, initial_value)
        register_addr = result.address
        test_pass("Register create", f"addr={result.address[:16]}... cost={result.cost}")
    except AlreadyExistsError:
        test_pass("Register create", "already exists (expected on re-run)")
    except Exception as e:
        test_fail("Register create", str(e))

    if register_addr:
        try:
            reg = client.register_get(register_addr)
            test_pass("Register get", f"value={reg.value[:16]}...")
        except Exception as e:
            test_fail("Register get", str(e))

        try:
            cost = client.register_cost(register_addr)
            test_pass("Register cost", f"cost={cost}")
        except Exception as e:
            test_fail("Register cost", str(e))
    else:
        test_skip("Register get", "no register address")
        test_skip("Register cost", "no register address")

    # 9. Large data round-trip (10 KB)
    try:
        large_data = os.urandom(10 * 1024)
        result = client.data_put_public(large_data)
        got = client.data_get_public(result.address)
        if got == large_data:
            test_pass("Large data round-trip (10KB)", f"addr={result.address[:16]}...")
        else:
            test_fail("Large data round-trip (10KB)", f"data mismatch: sent {len(large_data)}, got {len(got)}")
    except Exception as e:
        test_fail("Large data round-trip (10KB)", str(e))

    # --- Summary ---
    client.close()
    print()
    passed = sum(1 for _, s in results if s == "PASS")
    failed = sum(1 for _, s in results if s == "FAIL")
    skipped = sum(1 for _, s in results if s == "SKIP")
    total = len(results)

    color = GREEN if failed == 0 else RED
    print(f"{BOLD}Results: {color}{passed}/{total} passed{RESET}", end="")
    if failed:
        print(f", {RED}{failed} failed{RESET}", end="")
    if skipped:
        print(f", {YELLOW}{skipped} skipped{RESET}", end="")
    print()

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
