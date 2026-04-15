package antd

import (
	"context"
	"fmt"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"

	pb "github.com/WithAutonomi/ant-sdk/antd-go/proto/antd/v1"
)

// DefaultGrpcTarget is the default address of the antd gRPC server.
const DefaultGrpcTarget = "localhost:50051"

// DefaultGrpcTimeout is the default per-call timeout for gRPC requests.
const DefaultGrpcTimeout = 5 * time.Minute

// GrpcOption configures a GrpcClient.
type GrpcOption func(*GrpcClient)

// WithGrpcTimeout sets the per-call timeout for gRPC requests.
func WithGrpcTimeout(d time.Duration) GrpcOption {
	return func(c *GrpcClient) { c.timeout = d }
}

// WithDialOptions appends gRPC dial options.
func WithDialOptions(opts ...grpc.DialOption) GrpcOption {
	return func(c *GrpcClient) { c.dialOpts = append(c.dialOpts, opts...) }
}

// GrpcClient is a gRPC client for the antd daemon. It exposes the same
// methods as the REST Client, using the same model types and error types.
type GrpcClient struct {
	conn    *grpc.ClientConn
	timeout time.Duration

	dialOpts []grpc.DialOption

	health pb.HealthServiceClient
	data   pb.DataServiceClient
	chunk  pb.ChunkServiceClient
	file pb.FileServiceClient
}

// NewGrpcClientAutoDiscover creates a gRPC client that discovers the daemon target
// automatically. It reads the port file written by antd on startup, falling back
// to DefaultGrpcTarget. Returns the client, the resolved target, and any error.
func NewGrpcClientAutoDiscover(opts ...GrpcOption) (*GrpcClient, string, error) {
	target := DiscoverGrpcTarget()
	if target == "" {
		target = DefaultGrpcTarget
	}
	c, err := NewGrpcClient(target, opts...)
	return c, target, err
}

// NewGrpcClient creates a new gRPC client connected to the given target
// (e.g. "localhost:50051"). The connection is established lazily on first use.
func NewGrpcClient(target string, opts ...GrpcOption) (*GrpcClient, error) {
	c := &GrpcClient{
		timeout: DefaultGrpcTimeout,
	}
	for _, o := range opts {
		o(c)
	}

	// Default to insecure transport if no dial options are provided.
	if len(c.dialOpts) == 0 {
		c.dialOpts = append(c.dialOpts, grpc.WithTransportCredentials(insecure.NewCredentials()))
	}

	conn, err := grpc.NewClient(target, c.dialOpts...)
	if err != nil {
		return nil, fmt.Errorf("grpc dial: %w", err)
	}
	c.conn = conn

	c.health = pb.NewHealthServiceClient(conn)
	c.data = pb.NewDataServiceClient(conn)
	c.chunk = pb.NewChunkServiceClient(conn)
	c.file = pb.NewFileServiceClient(conn)

	return c, nil
}

// Close releases the underlying gRPC connection.
func (c *GrpcClient) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}

// ctx wraps the caller's context with the configured timeout.
func (c *GrpcClient) ctx(parent context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(parent, c.timeout)
}

// --- Error mapping ---

// errorFromGrpc converts a gRPC status error to the corresponding antd error
// type, matching the same typed errors returned by the REST client.
func errorFromGrpc(err error) error {
	if err == nil {
		return nil
	}
	st, ok := status.FromError(err)
	if !ok {
		return err
	}
	msg := st.Message()
	base := AntdError{Message: msg}

	switch st.Code() {
	case codes.InvalidArgument:
		base.StatusCode = 400
		return &BadRequestError{base}
	case codes.FailedPrecondition:
		base.StatusCode = 402
		return &PaymentError{base}
	case codes.NotFound:
		base.StatusCode = 404
		return &NotFoundError{base}
	case codes.AlreadyExists:
		base.StatusCode = 409
		return &AlreadyExistsError{base}
	case codes.ResourceExhausted:
		base.StatusCode = 413
		return &TooLargeError{base}
	case codes.Internal:
		base.StatusCode = 500
		return &InternalError{base}
	case codes.Unavailable:
		base.StatusCode = 502
		return &NetworkError{base}
	default:
		base.StatusCode = int(st.Code())
		return &base
	}
}

// --- Health (1 method) ---

// Health checks the antd daemon status.
func (c *GrpcClient) Health(ctx context.Context) (*HealthStatus, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.health.Check(ctx, &pb.HealthCheckRequest{})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &HealthStatus{
		OK:      resp.GetStatus() == "ok",
		Network: resp.GetNetwork(),
	}, nil
}

// --- Data (5 methods) ---

// DataPutPublic stores public immutable data on the network.
func (c *GrpcClient) DataPutPublic(ctx context.Context, data []byte) (*PutResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.data.PutPublic(ctx, &pb.PutPublicDataRequest{Data: data})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &PutResult{
		Cost:    resp.GetCost().GetAttoTokens(),
		Address: resp.GetAddress(),
	}, nil
}

// DataGetPublic retrieves public data by address.
func (c *GrpcClient) DataGetPublic(ctx context.Context, address string) ([]byte, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.data.GetPublic(ctx, &pb.GetPublicDataRequest{Address: address})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return resp.GetData(), nil
}

// DataPutPrivate stores private encrypted data on the network.
func (c *GrpcClient) DataPutPrivate(ctx context.Context, data []byte) (*PutResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.data.PutPrivate(ctx, &pb.PutPrivateDataRequest{Data: data})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &PutResult{
		Cost:    resp.GetCost().GetAttoTokens(),
		Address: resp.GetDataMap(),
	}, nil
}

// DataGetPrivate retrieves private data using a data map.
func (c *GrpcClient) DataGetPrivate(ctx context.Context, dataMap string) ([]byte, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.data.GetPrivate(ctx, &pb.GetPrivateDataRequest{DataMap: dataMap})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return resp.GetData(), nil
}

// DataCost estimates the cost of storing data.
func (c *GrpcClient) DataCost(ctx context.Context, data []byte) (string, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.data.GetCost(ctx, &pb.DataCostRequest{Data: data})
	if err != nil {
		return "", errorFromGrpc(err)
	}
	return resp.GetAttoTokens(), nil
}

// --- Chunks (2 methods) ---

// ChunkPut stores a raw chunk on the network.
func (c *GrpcClient) ChunkPut(ctx context.Context, data []byte) (*PutResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.chunk.Put(ctx, &pb.PutChunkRequest{Data: data})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &PutResult{
		Cost:    resp.GetCost().GetAttoTokens(),
		Address: resp.GetAddress(),
	}, nil
}

// ChunkGet retrieves a chunk by address.
func (c *GrpcClient) ChunkGet(ctx context.Context, address string) ([]byte, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.chunk.Get(ctx, &pb.GetChunkRequest{Address: address})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return resp.GetData(), nil
}

// --- Files (5 methods) ---

// FileUploadPublic uploads a local file to the network.
func (c *GrpcClient) FileUploadPublic(ctx context.Context, path string) (*FileUploadResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.file.UploadPublic(ctx, &pb.UploadFileRequest{Path: path})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &FileUploadResult{
		Address:         resp.GetAddress(),
		StorageCostAtto: resp.GetStorageCostAtto(),
		GasCostWei:      resp.GetGasCostWei(),
		ChunksStored:    resp.GetChunksStored(),
		PaymentModeUsed: resp.GetPaymentModeUsed(),
	}, nil
}

// FileDownloadPublic downloads a file from the network to a local path.
func (c *GrpcClient) FileDownloadPublic(ctx context.Context, address, destPath string) error {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	_, err := c.file.DownloadPublic(ctx, &pb.DownloadPublicRequest{
		Address:  address,
		DestPath: destPath,
	})
	return errorFromGrpc(err)
}

// DirUploadPublic uploads a local directory to the network.
func (c *GrpcClient) DirUploadPublic(ctx context.Context, path string) (*FileUploadResult, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.file.DirUploadPublic(ctx, &pb.UploadFileRequest{Path: path})
	if err != nil {
		return nil, errorFromGrpc(err)
	}
	return &FileUploadResult{
		Address:         resp.GetAddress(),
		StorageCostAtto: resp.GetStorageCostAtto(),
		GasCostWei:      resp.GetGasCostWei(),
		ChunksStored:    resp.GetChunksStored(),
		PaymentModeUsed: resp.GetPaymentModeUsed(),
	}, nil
}

// DirDownloadPublic downloads a directory from the network to a local path.
func (c *GrpcClient) DirDownloadPublic(ctx context.Context, address, destPath string) error {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	_, err := c.file.DirDownloadPublic(ctx, &pb.DownloadPublicRequest{
		Address:  address,
		DestPath: destPath,
	})
	return errorFromGrpc(err)
}

// FileCost estimates the cost of uploading a file.
func (c *GrpcClient) FileCost(ctx context.Context, path string, isPublic bool) (string, error) {
	ctx, cancel := c.ctx(ctx)
	defer cancel()

	resp, err := c.file.GetFileCost(ctx, &pb.FileCostRequest{
		Path:     path,
		IsPublic: isPublic,
	})
	if err != nil {
		return "", errorFromGrpc(err)
	}
	return resp.GetAttoTokens(), nil
}
