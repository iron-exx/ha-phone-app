package de.systemwerk.haphone.test

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person

object CallNotificationBuilder {
    const val CHANNEL_ID = "haphone_test_calls"
    private const val NOTIFICATION_ID = 1001

    fun show(context: Context, callId: String, isValid: Boolean, isExpired: Boolean) {
        val caller = Person.Builder().setName("HA-Phone Testanruf").setImportant(true).build()
        val fullScreenIntent = PendingIntent.getActivity(
            context, 0,
            Intent(context, IncomingCallActivity::class.java).putExtra("callId", callId),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val answerIntent = PendingIntent.getActivity(
            context, 1,
            Intent(context, IncomingCallActivity::class.java).putExtra("callId", callId),
            PendingIntent.FLAG_IMMUTABLE
        )
        val declineIntent = PendingIntent.getActivity(
            context, 2,
            Intent(context, IncomingCallActivity::class.java).putExtra("callId", callId),
            PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(caller, declineIntent, answerIntent))
            .setSmallIcon(android.R.drawable.sym_call_incoming)
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
        android.util.Log.i("HAPhoneTest", "notification shown callId=$callId isValid=$isValid isExpired=$isExpired")
        notificationManager.notify(NOTIFICATION_ID, builder.build())
    }
}
