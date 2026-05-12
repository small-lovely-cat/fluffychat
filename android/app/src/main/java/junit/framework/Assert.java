package junit.framework;

/**
 * Runtime compatibility shim for Tencent Soter release builds.
 *
 * <p>Soter 2.0.7 incorrectly references JUnit's Assert class from production
 * code. Android release artifacts do not package JUnit, so we provide the
 * minimal APIs that Soter calls at runtime instead of shipping the full test
 * dependency in the app.</p>
 */
public final class Assert {

    private Assert() {
        throw new AssertionError("No instances.");
    }

    /**
     * Verifies the supplied condition.
     *
     * @param condition condition expected to be true
     */
    public static void assertTrue(boolean condition) {
        if (!condition) {
            throw new AssertionError();
        }
    }

    /**
     * Verifies the supplied condition and keeps the original error message.
     *
     * @param message message attached to the failure
     * @param condition condition expected to be true
     */
    public static void assertTrue(String message, boolean condition) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    /**
     * Verifies the supplied reference is not null.
     *
     * @param object object expected to be non-null
     */
    public static void assertNotNull(Object object) {
        if (object == null) {
            throw new AssertionError();
        }
    }

    /**
     * Verifies the supplied reference is not null and keeps the original error
     * message.
     *
     * @param message message attached to the failure
     * @param object object expected to be non-null
     */
    public static void assertNotNull(String message, Object object) {
        if (object == null) {
            throw new AssertionError(message);
        }
    }
}
