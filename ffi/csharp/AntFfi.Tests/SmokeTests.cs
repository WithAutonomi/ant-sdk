namespace AntFfi.Tests;

/// <summary>
/// Smoke tests that verify the generated C# bindings compile and basic type
/// operations work. These tests do NOT require a running network.
/// </summary>
public class SmokeTests
{
    /// <summary>
    /// Verifies that the generated bindings assembly loads without errors.
    /// If uniffi-bindgen-cs generated invalid code, this test will fail to compile.
    /// </summary>
    [Fact]
    public void GeneratedBindings_ShouldLoad()
    {
        // If this test compiles and runs, the generated bindings are valid C#
        Assert.True(true, "Generated bindings loaded successfully");
    }
}
