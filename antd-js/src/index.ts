export type {
  HealthStatus,
  PutResult,
  PointerTarget,
  Pointer,
  Scratchpad,
  GraphDescendant,
  GraphEntry,
  Register,
  Vault,
  ArchiveEntry,
  Archive,
} from "./models.js";

export {
  AntdError,
  NotFoundError,
  AlreadyExistsError,
  ForkError,
  BadRequestError,
  PaymentError,
  NetworkError,
  TooLargeError,
  InternalError,
  fromHttpStatus,
} from "./errors.js";

export { RestClient } from "./rest-client.js";
export type { RestClientOptions } from "./rest-client.js";

import { RestClient, type RestClientOptions } from "./rest-client.js";

/** Create a REST client for the antd daemon. */
export function createClient(options?: RestClientOptions): RestClient {
  return new RestClient(options);
}
