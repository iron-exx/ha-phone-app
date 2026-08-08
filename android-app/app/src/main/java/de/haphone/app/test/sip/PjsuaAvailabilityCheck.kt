package de.haphone.app.test.sip

import org.pjsip.pjsua2.Endpoint

/**
 * Compile-time smoke check (Plan 02, Task 2): confirms the sip-core
 * Gradle module's generated PJSUA2 Java bindings are visible to :app.
 * Superseded by PjsuaEndpointHolder.kt in Plan 04, which owns the real
 * Endpoint lifecycle -- this file is deleted there once that exists.
 */
internal fun pjsuaBindingsAvailable(): Boolean = Endpoint::class.java.name.isNotEmpty()
