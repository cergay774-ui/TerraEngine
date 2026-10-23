package com.flurocup.app.crash

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.flurocup.app.R

/** After a crash, shows what happened once, with a button to copy the report. */
@Composable
fun CrashReportDialog() {
    val context = LocalContext.current
    var report by remember { mutableStateOf(CrashLog.take(context)) }
    val text = report ?: return
    val copied = stringResource(R.string.crash_copied)
    AlertDialog(
        onDismissRequest = { report = null },
        title = { Text(stringResource(R.string.crash_title)) },
        text = {
            SelectionContainer(Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState())) {
                Text(
                    text = stringResource(R.string.crash_message) + "\n\n" + text,
                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace, fontSize = 11.sp),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("FluroCup crash", text))
                Toast.makeText(context, copied, Toast.LENGTH_SHORT).show()
                report = null
            }) { Text(stringResource(R.string.crash_copy)) }
        },
        dismissButton = {
            TextButton(onClick = { report = null }) { Text(stringResource(R.string.crash_close)) }
        },
    )
}
