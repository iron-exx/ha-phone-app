package de.haphone.app.test.sip

import org.junit.Assert.assertEquals
import org.junit.Test

class CodecConfigTest {
    @Test
    fun orderedListMatchesResearchedPriorities() {
        assertEquals(
            listOf("opus/48000" to 255, "g722/16000" to 200, "pcma/8000" to 150, "pcmu/8000" to 150),
            CodecPriorities.ordered,
        )
    }

    @Test
    fun applyingPrioritiesCallsApplierForEachCodecInOrder() {
        val calls = mutableListOf<Pair<String, Int>>()
        val applier = object : CodecPriorityApplier {
            override fun setPriority(codecId: String, priority: Int) { calls.add(codecId to priority) }
        }
        CodecPriorities.ordered.forEach { (codec, priority) -> applier.setPriority(codec, priority) }
        assertEquals(CodecPriorities.ordered, calls)
    }
}
