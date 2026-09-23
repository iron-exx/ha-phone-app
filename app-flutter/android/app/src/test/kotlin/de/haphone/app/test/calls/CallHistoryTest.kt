package de.haphone.app.test.calls

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CallHistoryTest {
    private fun entry(id: String, startedAt: Long = 1_000) =
        CallHistoryEntry(id, "16", "türklingel", "incoming", video = true, startedAtMs = startedAt)

    @Test
    fun `new entries go first and replace an entry with the same id`() {
        val list = CallHistory.add(CallHistory.add(emptyList(), entry("a")), entry("b"))
        assertEquals(listOf("b", "a"), list.map { it.id })
        assertEquals(listOf("a", "b"), CallHistory.add(list, entry("a")).map { it.id })
    }

    @Test
    fun `history is capped`() {
        var list = emptyList<CallHistoryEntry>()
        repeat(CallHistory.MAX_ENTRIES + 5) { list = CallHistory.add(list, entry("id$it")) }
        assertEquals(CallHistory.MAX_ENTRIES, list.size)
        assertEquals("id${CallHistory.MAX_ENTRIES + 4}", list.first().id)
    }

    @Test
    fun `unanswered incoming call has no duration`() {
        val ended = CallHistory.markEnded(listOf(entry("a")), "a", 60_000).single()
        assertFalse(ended.answered)
        assertEquals(0, ended.durationSec)
    }

    @Test
    fun `duration counts from answer to end`() {
        val answered = CallHistory.markAnswered(listOf(entry("a")), "a", 10_000)
        val ended = CallHistory.markEnded(answered, "a", 72_500).single()
        assertTrue(ended.answered)
        assertEquals(62, ended.durationSec)
    }

    @Test
    fun `second end or answer does not overwrite the first`() {
        var list = CallHistory.markAnswered(listOf(entry("a")), "a", 10_000)
        list = CallHistory.markAnswered(list, "a", 20_000)
        list = CallHistory.markEnded(list, "a", 30_000)
        list = CallHistory.markEnded(list, "a", 90_000)
        assertEquals(20, list.single().durationSec)
    }

    @Test
    fun `remove drops only the given entry`() {
        val list = listOf(entry("a"), entry("b"))
        assertEquals(listOf("b"), CallHistory.remove(list, "a").map { it.id })
    }
}
