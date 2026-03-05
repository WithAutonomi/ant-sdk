using Antd.Sdk;
using Antd.Sdk.Tests;

var transport = "rest";
string? endpoint = null;

for (int i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--transport" or "-t" when i + 1 < args.Length:
            transport = args[++i];
            break;
        case "--endpoint" or "-e" when i + 1 < args.Length:
            endpoint = args[++i];
            break;
        case "--help" or "-h":
            Console.WriteLine("Usage: Antd.Sdk.Tests [options]");
            Console.WriteLine();
            Console.WriteLine("Options:");
            Console.WriteLine("  --transport, -t <rest|grpc>  Transport to use (default: rest)");
            Console.WriteLine("  --endpoint, -e <url>         Endpoint URL (default: auto)");
            Console.WriteLine("  --help, -h                   Show this help");
            return 0;
    }
}

using var client = AntdClient.Create(transport, endpoint);
var runner = new TestRunner(client, transport);
return await runner.RunAllAsync();
