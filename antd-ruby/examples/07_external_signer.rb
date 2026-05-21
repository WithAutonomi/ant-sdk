#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 07: External-signer flow — public file + single-chunk publish.
#
# PR #90 added prepare_upload_public / finalize_upload and prepare_chunk_upload
# / finalize_chunk_upload so the wallet key never has to live in the antd
# daemon. This example uses anvil deterministic account #0 as the external
# signer and exercises both round-trips end-to-end.
#
# See docs/external-signer-flow.md for the full reference; the IPaymentVault
# function selector and tuple ABI are encoded inline via the +eth+ gem.

require "eth"
require "fileutils"
require "tmpdir"
require_relative "../lib/antd"

# Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
# (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
# use this key anywhere except a throw-away local devnet.
ANVIL_KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
MAX_UINT256 = (1 << 256) - 1

# IPaymentVault.payForQuotes((address rewardsAddress, uint256 amount, bytes32 quoteHash)[])
# Selector 0xb6c2141b. See docs/external-signer-flow.md.
VAULT_ABI = [{
  "name" => "payForQuotes",
  "type" => "function",
  "stateMutability" => "nonpayable",
  "inputs" => [{
    "name" => "payments",
    "type" => "tuple[]",
    "components" => [
      { "name" => "rewardsAddress", "type" => "address" },
      { "name" => "amount",         "type" => "uint256" },
      { "name" => "quoteHash",      "type" => "bytes32" }
    ]
  }],
  "outputs" => []
}].freeze

# Minimal ERC-20 ABI for approve(). antToken is a standard ERC-20.
ERC20_ABI = [{
  "name" => "approve",
  "type" => "function",
  "stateMutability" => "nonpayable",
  "inputs" => [
    { "name" => "spender", "type" => "address" },
    { "name" => "value",   "type" => "uint256" }
  ],
  "outputs" => [{ "name" => "success", "type" => "bool" }]
}].freeze

# Run approve + payForQuotes on-chain for a daemon prepare response.
# Returns the quote_hash -> tx_hash map the daemon's finalize_* methods
# expect. Every entry maps to the same payForQuotes tx because every quote
# in the wave is paid in one batched call.
def external_signer_pay(rpc_url, vault_addr, token_addr, payments, key)
  # No on-chain work when every quoted chunk is already on-network.
  return {} if payments.empty?

  client = Eth::Client.create(rpc_url)

  vault_contract = Eth::Contract.from_abi(
    name: "IPaymentVault", address: vault_addr, abi: VAULT_ABI
  )
  erc20_contract = Eth::Contract.from_abi(
    name: "IERC20", address: token_addr, abi: ERC20_ABI
  )

  # approve(vault, MAX) — idempotent and cheap; example uses MAX so
  # subsequent flows in this run skip a fresh approval.
  #
  # transact_and_wait returns the receipt (a hash); the daemon's finalize_*
  # expects the tx hash as a plain string, so we extract it via #to_s which
  # is the canonical hex repr in eth-rb's receipt models.
  client.transact_and_wait(
    erc20_contract, "approve", vault_addr, MAX_UINT256,
    sender_key: key, gas_limit: 500_000
  )

  # payForQuotes — one tx covering every quote in this wave.
  tuples = payments.map do |p|
    qh_hex = p.quote_hash.start_with?("0x") ? p.quote_hash[2..] : p.quote_hash
    [
      p.rewards_address,
      Integer(p.amount),
      [qh_hex].pack("H*"),
    ]
  end
  pay_receipt = client.transact_and_wait(
    vault_contract, "payForQuotes", tuples,
    sender_key: key, gas_limit: 1_000_000
  )
  # eth-rb's transact_and_wait returns [tx_hash_string, success_bool] in
  # recent versions; older versions return a receipt hash. Handle both.
  pay_tx =
    if pay_receipt.is_a?(Array)
      pay_receipt[0]
    elsif pay_receipt.is_a?(Hash)
      pay_receipt["transactionHash"] || pay_receipt[:transactionHash]
    else
      pay_receipt.to_s
    end

  # Every quote in this wave was paid in the same call.
  payments.each_with_object({}) { |p, h| h[p.quote_hash] = pay_tx }
end

client = Antd::Client.new
key = Eth::Key.new(priv: ANVIL_KEY)

Dir.mktmpdir("antd-ruby-07-extsig-") do |tmp|
  # --- 1. file upload via external signer -----------------------------
  src = File.join(tmp, "file.bin")
  File.write(src, "hello external signer from ruby (file)\n" * 16)

  file_prep = client.prepare_upload_public(src)
  puts "File prepare: upload_id=#{file_prep.upload_id[0, 16]}..., " \
       "payment_type=#{file_prep.payment_type}, " \
       "payments=#{file_prep.payments.length}, total_amount=#{file_prep.total_amount}"

  file_tx_hashes = external_signer_pay(
    file_prep.rpc_url, file_prep.payment_vault_address,
    file_prep.payment_token_address, file_prep.payments, key
  )
  file_fin = client.finalize_upload(file_prep.upload_id, file_tx_hashes)
  puts "File finalize: data_map_address=#{file_fin.data_map_address}, " \
       "chunks_stored=#{file_fin.chunks_stored}"

  dst = File.join(tmp, "file.bin.downloaded")
  client.file_get_public(file_fin.data_map_address, dst)
  unless File.binread(dst) == File.binread(src)
    warn "file round-trip mismatch"
    exit 1
  end
  puts "File round-trip OK!"

  # --- 2. single-chunk publish via external signer --------------------
  chunk_data = ("hello external signer from ruby (chunk)\n" * 8).b
  chunk_prep = client.prepare_chunk_upload(chunk_data)
  if chunk_prep.already_stored
    puts "Chunk prepare: already_stored, address=#{chunk_prep.address}"
  else
    puts "Chunk prepare: upload_id=#{chunk_prep.upload_id[0, 16]}..., " \
         "address=#{chunk_prep.address}, payments=#{chunk_prep.payments.length}, " \
         "total_amount=#{chunk_prep.total_amount}"
    chunk_tx_hashes = external_signer_pay(
      chunk_prep.rpc_url, chunk_prep.payment_vault_address,
      chunk_prep.payment_token_address, chunk_prep.payments, key
    )
    addr = client.finalize_chunk_upload(chunk_prep.upload_id, chunk_tx_hashes)
    unless addr == chunk_prep.address
      warn "chunk address mismatch: #{addr} != #{chunk_prep.address}"
      exit 1
    end
    puts "Chunk finalize: address=#{addr}"
  end

  got = client.chunk_get(chunk_prep.address)
  unless got == chunk_data
    warn "chunk round-trip mismatch"
    exit 1
  end
  puts "Chunk round-trip OK!"
end

puts "\n07_external_signer OK!"
