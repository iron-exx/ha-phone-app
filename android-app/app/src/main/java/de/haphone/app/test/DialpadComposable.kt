package de.haphone.app.test

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val KEYS = listOf(
    "1" to "", "2" to "ABC", "3" to "DEF",
    "4" to "GHI", "5" to "JKL", "6" to "MNO",
    "7" to "PQRS", "8" to "TUV", "9" to "WXYZ",
    "*" to "", "0" to "+", "#" to "",
)

/** Reused 3x -- outgoing dial (CALL-03), in-call DTMF (CALL-02), blind
 * transfer target (CALL-04) per D-13/D-14. Minimum 48dp tap target per
 * 02-UI-SPEC.md accessibility floor. */
@Composable
fun DialpadComposable(onDigit: (Char) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        KEYS.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { (digit, letters) ->
                    Button(onClick = { onDigit(digit.first()) }, modifier = Modifier.size(64.dp)) {
                        Column {
                            Text(digit, fontSize = 20.sp, textAlign = TextAlign.Center)
                            if (letters.isNotEmpty()) {
                                Text(letters, fontSize = 14.sp, textAlign = TextAlign.Center)
                            }
                        }
                    }
                }
            }
        }
    }
}
