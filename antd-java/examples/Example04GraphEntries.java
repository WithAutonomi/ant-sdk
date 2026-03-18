import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.GraphDescendant;
import com.autonomi.antd.models.GraphEntry;
import com.autonomi.antd.models.PutResult;

import java.util.Collections;
import java.util.List;

/**
 * Example 04 — Create and read graph entries (DAG nodes).
 */
public class Example04GraphEntries {
    public static void main(String[] args) {
        try (var client = new AntdClient()) {
            // Create a graph entry
            PutResult result = client.graphEntryPut(
                    "your-secret-key-hex",
                    Collections.emptyList(),
                    "content-hex-32-bytes",
                    List.of(new GraphDescendant("descendant-public-key", "descendant-content")));
            System.out.println("Created at: " + result.address());

            // Read it back
            GraphEntry entry = client.graphEntryGet(result.address());
            System.out.println("Owner:       " + entry.owner());
            System.out.println("Content:     " + entry.content());
            System.out.println("Descendants: " + entry.descendants().size());

            // Check existence
            boolean exists = client.graphEntryExists(result.address());
            System.out.println("Exists: " + exists);

            // Estimate cost
            String cost = client.graphEntryCost("your-public-key-hex");
            System.out.println("Cost estimate: " + cost + " atto");
        }
    }
}
