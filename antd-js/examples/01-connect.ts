/**
 * Example 01: Connect to antd daemon and check health.
 *
 * Prerequisite: antd daemon running locally (default: http://localhost:8082).
 */

import { createClient } from "../src/index.js";

const client = createClient();
const status = await client.health();

console.log(`Daemon healthy: ${status.ok}`);
console.log(`Network: ${status.network}`);

if (!status.ok) {
  console.log("ERROR: antd daemon is not healthy");
  process.exit(1);
}

console.log("Connection OK!");
