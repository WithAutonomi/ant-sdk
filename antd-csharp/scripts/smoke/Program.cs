// Smoke consumer for the packed Antd.Sdk .nupkg (run by publish-nuget.yml).
// Constructs both transports against a dead endpoint — no daemon needed —
// to prove the package resolves, loads, and exposes the public factory.
using Antd.Sdk;

using var rest = AntdClient.CreateRest("http://127.0.0.1:1");
using var grpc = AntdClient.CreateGrpc("http://127.0.0.1:1");
var asm = typeof(AntdClient).Assembly.GetName();
Console.WriteLine($"{asm.Name} {asm.Version}: rest={rest.GetType().Name} grpc={grpc.GetType().Name} OK");
