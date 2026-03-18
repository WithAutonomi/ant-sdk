import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.PutResult;

/**
 * Example 02 — Store and retrieve public immutable data.
 */
public class Example02PublicData {
    public static void main(String[] args) {
        try (var client = new AntdClient()) {
            // Store data
            byte[] payload = "Hello, Autonomi!".getBytes();
            PutResult result = client.dataPutPublic(payload);
            System.out.println("Stored at: " + result.address());
            System.out.println("Cost:      " + result.cost() + " atto");

            // Retrieve data
            byte[] retrieved = client.dataGetPublic(result.address());
            System.out.println("Retrieved: " + new String(retrieved));
        }
    }
}
