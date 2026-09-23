package de.haphone.app.test

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Notification actions for call waiting; runs on the main thread like the PJSIP calls require. */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext as HAPhoneTestApplication
        CallNotificationBuilder.cancelWaiting(context)
        runCatching {
            when (intent.action) {
                ACTION_ANSWER_WAITING -> {
                    if (app.sipCallController.answerWaiting()) app.calls.acceptWaiting()
                    context.startActivity(
                        Intent(context, MainActivity::class.java)
                            .putExtra("route", "active_call")
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    )
                }
                ACTION_REJECT_WAITING -> app.sipCallController.rejectWaiting()
            }
        }.onFailure { android.util.Log.w("CallActionReceiver", "action ${intent.action} failed", it) }
    }

    companion object {
        const val ACTION_ANSWER_WAITING = "de.haphone.app.test.ANSWER_WAITING"
        const val ACTION_REJECT_WAITING = "de.haphone.app.test.REJECT_WAITING"

        fun pendingIntent(context: Context, action: String): PendingIntent = PendingIntent.getBroadcast(
            context,
            action.hashCode(),
            Intent(context, CallActionReceiver::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
