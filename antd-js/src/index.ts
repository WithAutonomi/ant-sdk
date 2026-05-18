export type {
  HealthStatus,
  PutResult,
  FileUploadResult,
  WalletAddress,
  WalletBalance,
  PaymentInfo,
  CandidateNodeEntry,
  PoolCommitmentEntry,
  PrepareUploadResult,
  FinalizeUploadResult,
  PrepareChunkResult,
  UploadCostEstimate,
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
  ServiceUnavailableError,
  fromHttpStatus,
} from "./errors.js";

export { RestClient } from "./rest-client.js";
export type { RestClientOptions } from "./rest-client.js";

export { discoverDaemonUrl } from "./discover.js";

import { RestClient, type RestClientOptions } from "./rest-client.js";

/** Create a REST client for the antd daemon. */
export function createClient(options?: RestClientOptions): RestClient {
  return new RestClient(options);
}
