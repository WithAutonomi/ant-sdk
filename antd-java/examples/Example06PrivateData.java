import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.PutResult;

/**
 * Example 06 — Store and retrieve private (encrypted) data.
 */
public class Example06PrivateData {
    public static void main(String[] args) {
        try (var client = new AntdClient()) {
            // Store private data (encrypted by the daemon)
            byte[] secret = "sensitive enterprise data".getBytes();
            PutResult result = client.dataPutPrivate(secret);
            System.out.println("Data map: " + result.address());
            System.out.println("Cost:     " + result.cost() + " atto");

            // Retrieve private data (decrypted by the daemon)
            byte[] retrieved = client.dataGetPrivate(result.address());
            System.out.println("Retrieved: " + new String(retrieved));

            // Estimate cost
            String cost = client.dataCost(secret);
            System.out.println("Estimated cost: " + cost + " atto");
        }
    }
}
