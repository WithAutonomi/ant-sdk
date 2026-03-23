defmodule Antd.AntdError do
  @moduledoc "Base error for all antd errors."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.BadRequestError do
  @moduledoc "Invalid request parameters (HTTP 400)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.PaymentError do
  @moduledoc "Insufficient funds or payment failure (HTTP 402)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.NotFoundError do
  @moduledoc "Resource not found on the network (HTTP 404)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.AlreadyExistsError do
  @moduledoc "Resource already exists (HTTP 409)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.ForkError do
  @moduledoc "Version conflict or fork detected (HTTP 409)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.TooLargeError do
  @moduledoc "Payload too large (HTTP 413)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.InternalError do
  @moduledoc "Internal server error (HTTP 500)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.NotImplementedError do
  @moduledoc "Operation not implemented by the daemon (HTTP 501)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.NetworkError do
  @moduledoc "Daemon cannot reach the network (HTTP 502)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.Errors do
  @moduledoc false

  @doc "Returns the appropriate error struct for an HTTP status code."
  @spec error_for_status(integer(), String.t()) :: Exception.t()
  def error_for_status(status_code, message) do
    case status_code do
      400 -> %Antd.BadRequestError{message: message, status_code: 400}
      402 -> %Antd.PaymentError{message: message, status_code: 402}
      404 -> %Antd.NotFoundError{message: message, status_code: 404}
      409 -> %Antd.AlreadyExistsError{message: message, status_code: 409}
      413 -> %Antd.TooLargeError{message: message, status_code: 413}
      500 -> %Antd.InternalError{message: message, status_code: 500}
      501 -> %Antd.NotImplementedError{message: message, status_code: 501}
      502 -> %Antd.NetworkError{message: message, status_code: 502}
      _ -> %Antd.AntdError{message: message, status_code: status_code}
    end
  end
end
