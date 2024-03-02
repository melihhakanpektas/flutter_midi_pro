package com.melihhakanpektas.midisynthesizer.sampled;

public interface AutoCloseable {

    /**
     * Closes the object and release any system resources it holds.
     */
    void close() throws Exception;
}
