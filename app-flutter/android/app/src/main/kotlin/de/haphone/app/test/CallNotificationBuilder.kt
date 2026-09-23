package de.haphone.app.test

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person

object CallNotificationBuilder {
    const val CHANNEL_ID = "haphone_test_calls"
    private const val NOTIFICATION_ID = 1001
    private const val WAITING_NOTIFICATION_ID = 1002

    fun show(
        context: Context,
        callId: String,
        callType: String,
        isValid: Boolean,
        isExpired: Boolean,
        callerName: String? = null,
    ) {
        val name = callerName?.takeIf { it.isNotBlank() } ?: when (callType) {
            "video", "door" -> "HA-Phone Türstation"
            else -> "HA-Phone Testanruf"
        }
        val caller = Person.Builder().setName(name).setImportant(true).build()
        fun ringing(requestCode: Int, action: String?) = PendingIntent.getActivity(
            context, requestCode,
            IncomingCallActivity.intent(context, callId, callType, name, action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val fullScreenIntent = ringing(0, null)
        val answerIntent = ringing(1, IncomingCallActivity.ACTION_ANSWER)
        val declineIntent = ringing(2, IncomingCallActivity.ACTION_DECLINE)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(caller, declineIntent, answerIntent))
            .setSmallIcon(R.drawable.ic_stat_haphone)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .addPerson(caller)

        val notificationManager = NotificationManagerCompat.from(context)
        if (notificationManager.canUseFullScreenIntent()) {
            builder.setFullScreenIntent(fullScreenIntent, true)
        }
        // Log validity/expiry to logcat for the manual test procedure (D-09). This
        // notify() call always runs, unconditionally, regardless of what isValid or
        // isExpired evaluate to -- there is no branch anywhere above that returns
        // early or otherwise avoids calling notify() based on their values.
        android.util.Log.i("HAPhoneTest", "notification shown callId=$callId callType=$callType isValid=$isValid isExpired=$isExpired")
        notificationManager.notify(NOTIFICATION_ID, builder.build())
    }

    /**
     * Dismiss the incoming-call notification. Telecom's own `disconnect()`
     * (see [CallRegistration.reportIncomingCall]) ends the call at the
     * platform/Telecom layer but does NOT remove a notification this app
     * posted itself -- CallStyle notifications built manually (as opposed to
     * a Telecom-managed one) require an explicit cancel(). Without this, an
     * invalid/expired push's ringing UI would linger even though the call
     * session underneath is already gone (code review CR-01 follow-up).
     */
    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    /** Call waiting: heads-up with Annehmen (holds the current call) / Ablehnen, no full screen. */
    fun showWaiting(context: Context, callId: String, callerName: String?) {
        val name = callerName?.takeIf { it.isNotBlank() } ?: callId
        val caller = Person.Builder().setName(name).setImportant(true).build()
        val answer = CallActionReceiver.pendingIntent(context, CallActionReceiver.ACTION_ANSWER_WAITING)
        val decline = CallActionReceiver.pendingIntent(context, CallActionReceiver.ACTION_REJECT_WAITING)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(caller, decline, answer))
            .setSmallIcon(R.drawable.ic_stat_haphone)
            .setContentText("Anklopfen: $name")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOnlyAlertOnce(true)
            .addPerson(caller)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(WAITING_NOTIFICATION_ID, notification) }
            .onFailure { android.util.Log.w("HAPhoneTest", "call waiting notification failed", it) }
    }

    fun cancelWaiting(context: Context) {
        NotificationManagerCompat.from(context).cancel(WAITING_NOTIFICATION_ID)
    }
}
