package com.autonomi.examples;

import com.autonomi.antd.AntdClient;
import com.autonomi.antd.errors.*;

/**
 * Example 05 — Error handling with typed exceptions.
 */
public class Example05ErrorHandling {
    public static void main(String[] args) {
        try (var client = new AntdClient()) {
            byte[] data = client.dataGetPublic("nonexistent-address");
            System.out.println("Retrieved: " + new String(data));
        } catch (NotFoundException e) {
            System.out.println("Data not found on the network");
            System.out.println("Status code: " + e.getStatusCode());
        } catch (PaymentException e) {
            System.out.println("Insufficient funds: " + e.getMessage());
        } catch (NetworkException e) {
            System.out.println("Network unreachable: " + e.getMessage());
        } catch (AntdException e) {
            System.out.println("Unexpected error (" + e.getStatusCode() + "): " + e.getMessage());
        }
    }
}
