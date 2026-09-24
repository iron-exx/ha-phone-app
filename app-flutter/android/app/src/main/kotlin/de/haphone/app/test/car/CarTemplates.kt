package de.haphone.app.test.car

import android.Manifest
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Tab
import androidx.car.app.model.TabContents
import androidx.car.app.model.TabTemplate
import androidx.car.app.model.Template
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import de.haphone.app.test.HAPhoneTestApplication
import de.haphone.app.test.R
import de.haphone.app.test.ring.DoorOpenClient

/** The four sections of the car UI. */
enum class CarSection(val id: String, val title: String, val icon: Int, val empty: String) {
    FAVORITES("fav", "Favoriten", R.drawable.ic_car_star, "Keine Favoriten – in der App am Handy mit dem Stern markieren"),
    RECENTS("recent", "Verlauf", R.drawable.ic_car_history, "Noch keine Anrufe"),
    CONTACTS("contacts", "Kontakte", R.drawable.ic_car_person, "Keine Nebenstellen – App am Handy einmal öffnen"),
    DOORS("doors", "Haustür", R.drawable.ic_car_door, "Keine Türstation eingerichtet"),
}

/** Shared helpers of all car screens: rows, dialling, the presence fetch. */
private class CarUi(private val carContext: CarContext) {
    val app = carContext.applicationContext as HAPhoneTestApplication
    private val main = Handler(Looper.getMainLooper())

    fun icon(res: Int, tint: CarColor? = null): CarIcon =
        CarIcon.Builder(IconCompat.createWithResource(carContext, res)).apply { tint?.let { setTint(it) } }.build()

    fun listLimit(): Int = runCatching {
        if (carContext.carAppApiLevel < 2) return CarLists.DEFAULT_LIMIT
        carContext.getCarService(ConstraintManager::class.java).getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
    }.getOrDefault(CarLists.DEFAULT_LIMIT)

    fun toast(text: String) = CarToast.makeText(carContext, text, CarToast.LENGTH_LONG).show()

    /** Dials through the normal native call path; Android Auto then shows its in-call view. */
    fun dial(number: String) {
        if (!app.hasValidCredentials()) {
            toast("HA-Phone ist nicht eingerichtet – App am Handy koppeln")
            return
        }
        if (ContextCompat.checkSelfPermission(carContext, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            toast("Mikrofon-Berechtigung fehlt – einmal in der App am Handy erlauben")
            return
        }
        if (!app.placeCall(number)) {
            toast("Schon zwei Gespräche aktiv")
            return
        }
        app.sipMethodChannel?.invokeMethod("navigateTo", "active_call")
    }

    fun rowIcon(kind: CarIconKind): CarIcon = when (kind) {
        CarIconKind.PERSON -> icon(R.drawable.ic_car_person)
        CarIconKind.DOOR -> icon(R.drawable.ic_car_door)
        CarIconKind.STAR -> icon(R.drawable.ic_car_star, CarColor.YELLOW)
        CarIconKind.INCOMING -> icon(R.drawable.ic_car_call_in, CarColor.GREEN)
        CarIconKind.OUTGOING -> icon(R.drawable.ic_car_call_out, CarColor.BLUE)
        CarIconKind.MISSED -> icon(R.drawable.ic_car_call_missed, CarColor.RED)
    }

    fun itemList(section: CarSection, presence: Map<String, CarPresence>, screen: Screen): ItemList {
        val dir = app.carDirectory.load()
        val limit = listLimit()
        val rows = when (section) {
            CarSection.FAVORITES -> CarLists.favorites(dir, presence, limit)
            CarSection.RECENTS -> CarLists.recents(app.callHistory.all(), dir, System.currentTimeMillis(), limit = limit)
            CarSection.CONTACTS -> CarLists.contacts(dir, presence, limit)
            CarSection.DOORS -> CarLists.doors(dir, limit)
        }
        return ItemList.Builder().setNoItemsMessage(section.empty).apply {
            rows.forEach { row ->
                addItem(
                    Row.Builder()
                        .setTitle(row.title)
                        .addText(row.subtitle)
                        .setImage(rowIcon(row.icon), Row.IMAGE_TYPE_ICON)
                        .setOnClickListener {
                            val door = if (row.opensDoor) dir.find(row.number) else null
                            if (door != null) screen.screenManager.push(CarDoorScreen(carContext, door)) else dial(row.number)
                        }
                        .build(),
                )
            }
        }.build()
    }

    /** Presence for Kontakte/Favoriten, fetched natively (the Dart poller only runs in the phone UI). */
    fun fetchPresence(onDone: (Map<String, CarPresence>) -> Unit) {
        val auth = app.getDeviceAuth()
        Thread {
            val result = CarPresenceClient.fetch(auth["apiHost"].orEmpty(), auth["deviceId"].orEmpty(), auth["deviceToken"].orEmpty())
            main.post { onDone(result) }
        }.start()
    }
}

/**
 * Root: tabs Favoriten / Verlauf / Kontakte / Haustür on hosts with Car API level 6+,
 * else a plain menu list that opens one [CarSectionScreen] per section.
 */
class CarRootScreen(carContext: CarContext) : Screen(carContext) {
    private val ui = CarUi(carContext)
    private var active = CarSection.FAVORITES
    private var presence: Map<String, CarPresence> = emptyMap()

    init {
        CarScreens.register(this)
        refreshPresence()
    }

    private fun refreshPresence() = ui.fetchPresence {
        presence = it
        invalidate()
    }

    override fun onGetTemplate(): Template =
        if (carContext.carAppApiLevel >= 6) tabs() else menu()

    private fun tabs(): Template {
        val builder = TabTemplate.Builder(object : TabTemplate.TabCallback {
            override fun onTabSelected(tabContentId: String) {
                active = CarSection.entries.firstOrNull { it.id == tabContentId } ?: CarSection.FAVORITES
                if (active == CarSection.CONTACTS || active == CarSection.FAVORITES) refreshPresence()
                invalidate()
            }
        }).setHeaderAction(Action.APP_ICON)
        CarSection.entries.forEach { s ->
            builder.addTab(Tab.Builder().setTitle(s.title).setIcon(ui.icon(s.icon)).setContentId(s.id).build())
        }
        val list = ListTemplate.Builder().setSingleList(ui.itemList(active, presence, this)).build()
        return builder.setTabContents(TabContents.Builder(list).build()).setActiveTabContentId(active.id).build()
    }

    private fun menu(): Template {
        val items = ItemList.Builder().apply {
            CarSection.entries.forEach { s ->
                addItem(
                    Row.Builder().setTitle(s.title).setImage(ui.icon(s.icon), Row.IMAGE_TYPE_ICON).setBrowsable(true)
                        .setOnClickListener { screenManager.push(CarSectionScreen(carContext, s)) }.build(),
                )
            }
        }.build()
        return ListTemplate.Builder().setTitle("HA-Phone").setHeaderAction(Action.APP_ICON).setSingleList(items).build()
    }
}

/** One section as its own screen (fallback for hosts without TabTemplate). */
class CarSectionScreen(carContext: CarContext, private val section: CarSection) : Screen(carContext) {
    private val ui = CarUi(carContext)
    private var presence: Map<String, CarPresence> = emptyMap()

    init {
        CarScreens.register(this)
        if (section == CarSection.CONTACTS || section == CarSection.FAVORITES) {
            ui.fetchPresence {
                presence = it
                invalidate()
            }
        }
    }

    override fun onGetTemplate(): Template =
        ListTemplate.Builder().setTitle(section.title).setHeaderAction(Action.BACK)
            .setSingleList(ui.itemList(section, presence, this)).build()
}

/** A door station: call it, open it (webhook doors, after a confirmation) and its Home Assistant actions. */
class CarDoorScreen(carContext: CarContext, private val door: CarEntry) : Screen(carContext) {
    private val ui = CarUi(carContext)

    override fun onGetTemplate(): Template {
        val actions = CarLists.doorActions(door, ui.app.doorActions.labelsFor(door.number))
        val items = ItemList.Builder().apply {
            actions.forEach { a ->
                val (icon, onClick) = when (a.kind) {
                    DoorAction.Kind.CALL -> ui.icon(R.drawable.ic_car_call, CarColor.GREEN) to { ui.dial(door.number) }
                    DoorAction.Kind.OPEN -> ui.icon(R.drawable.ic_car_lock_open, CarColor.YELLOW) to {
                        screenManager.push(CarConfirmOpenScreen(carContext, door))
                    }
                    DoorAction.Kind.HA_ACTION -> ui.icon(R.drawable.ic_car_home) to { runHaAction(a) }
                }
                addItem(Row.Builder().setTitle(a.label).setImage(icon, Row.IMAGE_TYPE_ICON).setOnClickListener(onClick).build())
            }
        }.build()
        return ListTemplate.Builder().setTitle(door.displayName).setHeaderAction(Action.BACK).setSingleList(items).build()
    }

    private fun runHaAction(a: DoorAction) {
        ui.app.runDoorAction(door.number, a.index) { error ->
            ui.toast(error ?: "${a.label}: erledigt")
        }
    }
}

/**
 * "Tür öffnen" asks once more: a stray tap while driving must not open the front door.
 * Same webhook as the phone's ringing-screen slider (POST /api/mobile/door-open).
 */
class CarConfirmOpenScreen(carContext: CarContext, private val door: CarEntry) : Screen(carContext) {
    private val ui = CarUi(carContext)
    private var busy = false

    override fun onGetTemplate(): Template {
        val open = Action.Builder().setTitle("Öffnen").setBackgroundColor(CarColor.GREEN)
            .setOnClickListener { open() }.build()
        val cancel = Action.Builder().setTitle("Abbrechen").setOnClickListener { finish() }.build()
        return MessageTemplate.Builder("${door.displayName} jetzt öffnen?")
            .setTitle("Tür öffnen")
            .setHeaderAction(Action.BACK)
            .setLoading(busy)
            // A loading MessageTemplate may carry neither icon nor actions (build() throws).
            .apply { if (!busy) setIcon(ui.icon(R.drawable.ic_car_lock_open, CarColor.YELLOW)).addAction(open).addAction(cancel) }
            .build()
    }

    private fun open() {
        if (busy) return
        busy = true
        invalidate()
        val auth = ui.app.getDeviceAuth()
        val main = Handler(Looper.getMainLooper())
        Thread {
            val outcome = DoorOpenClient.open(
                auth["apiHost"].orEmpty(), auth["deviceId"].orEmpty(), auth["deviceToken"].orEmpty(), door.number,
            )
            main.post {
                ui.toast(outcome.message?.let { "Tür nicht geöffnet: $it" } ?: "${door.displayName} geöffnet")
                finish()
            }
        }.start()
    }
}
