import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.HealthStatus;

/**
 * Example 01 — Connect to the antd daemon and check health.
 */
public class Example01Connect {
    public static void main(String[] args) {
        try (var client = new AntdClient()) {
            HealthStatus health = client.health();
            System.out.println("Daemon OK: " + health.ok());
            System.out.println("Network:   " + health.network());
        }
    }
}
