package com.flurocup.core.engine.media

import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Keeps read access to picked files after the app restarts, so projects can be reopened.
 * Not every source grants persistable access; those files stay readable until the app is closed.
 */
object MediaPermissions {
    fun persist(context: Context, uris: List<Uri>) {
        uris.forEach { uri ->
            runCatching {
                context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
    }
}
