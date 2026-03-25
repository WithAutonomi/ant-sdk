# frozen_string_literal: true

module Antd
  # Result of a health check.
  HealthStatus = Struct.new(:ok, :network, keyword_init: true)

  # Result of a put/create operation.
  PutResult = Struct.new(:cost, :address, keyword_init: true)

  # A descendant entry in a graph node.
  GraphDescendant = Struct.new(:public_key, :content, keyword_init: true)

  # A DAG node from the network.
  GraphEntry = Struct.new(:owner, :parents, :content, :descendants, keyword_init: true)

  # A single entry in a file archive.
  ArchiveEntry = Struct.new(:path, :address, :created, :modified, :size, keyword_init: true)

  # A collection of archive entries.
  Archive = Struct.new(:entries, keyword_init: true)

  # Wallet address result.
  WalletAddress = Struct.new(:address, keyword_init: true)

  # Wallet balance result.
  WalletBalance = Struct.new(:balance, :gas_balance, keyword_init: true)
end
