import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.FileUploadResult;

/**
 * Example 03 — Upload and download files.
 */
public class Example03Files {
    public static void main(String[] args) {
        try (var client = new AntdClient()) {
            // Upload a file
            FileUploadResult result = client.fileUploadPublic("/path/to/file.txt");
            System.out.println("Uploaded to:  " + result.address());
            System.out.println("Storage cost: " + result.storageCostAtto() + " atto");
            System.out.println("Gas cost:     " + result.gasCostWei() + " wei");
            System.out.println("Chunks:       " + result.chunksStored());
            System.out.println("Mode:         " + result.paymentModeUsed());

            // Download a file
            client.fileDownloadPublic(result.address(), "/path/to/output.txt");
            System.out.println("Downloaded successfully");

            // Estimate cost before uploading
            String cost = client.fileCost("/path/to/file.txt", true);
            System.out.println("Estimated cost: " + cost + " atto");
        }
    }
}
