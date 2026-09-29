package de.haphone.app.test.calls

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PreviewCameraPathsTest {
    @Test
    fun onlyPlainCameraEntitiesAreAccepted() {
        assertTrue(PreviewCameraPaths.isCameraEntity("camera.garten_2"))
        assertFalse(PreviewCameraPaths.isCameraEntity("camera."))
        assertFalse(PreviewCameraPaths.isCameraEntity("light.flur"))
        assertFalse(PreviewCameraPaths.isCameraEntity("camera.a/../b"))
        assertFalse(PreviewCameraPaths.isCameraEntity("camera.Garten"))
    }

    @Test
    fun snapshotPath() {
        assertEquals("/api/mobile/cameras/camera.garten/snapshot", PreviewCameraPaths.snapshot("camera.garten"))
    }

    @Test
    fun sampleSizeHalvesUntilCloseToTheTarget() {
        assertEquals(1, PreviewCameraPaths.sampleSize(640, 960))
        assertEquals(1, PreviewCameraPaths.sampleSize(1280, 960))
        assertEquals(2, PreviewCameraPaths.sampleSize(1920, 960))
        assertEquals(4, PreviewCameraPaths.sampleSize(3840, 960))
        assertEquals(1, PreviewCameraPaths.sampleSize(0, 960))
    }
}
