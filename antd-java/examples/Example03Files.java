import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.PutResult;

/**
 * Example 03 — Upload and download files.
 */
public class Example03Files {
    public static void main(String[] args) {
        try (var client = new AntdClient()) {
            // Upload a file
            PutResult result = client.fileUploadPublic("/path/to/file.txt");
            System.out.println("Uploaded to: " + result.address());
            System.out.println("Cost:        " + result.cost() + " atto");

            // Download a file
            client.fileDownloadPublic(result.address(), "/path/to/output.txt");
            System.out.println("Downloaded successfully");

            // Estimate cost before uploading
            String cost = client.fileCost("/path/to/file.txt", true, false);
            System.out.println("Estimated cost: " + cost + " atto");
        }
    }
}
