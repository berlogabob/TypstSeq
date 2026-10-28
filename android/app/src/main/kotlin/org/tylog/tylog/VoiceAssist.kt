package org.tylog.tylog

import android.content.Intent
import android.os.Bundle
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService
import android.speech.RecognitionService

/// Makes TyLog selectable as the digital assistant (Settings > Default apps).
/// Invoking it (power long-press, home-corner swipe) opens the audio recorder.
class TyLogVoiceInteractionService : VoiceInteractionService()

class TyLogSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession = TyLogSession(this)
}

class TyLogSession(private val service: TyLogSessionService) : VoiceInteractionSession(service) {
    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        startAssistantActivity(
            Intent(service, MainActivity::class.java)
                .setAction(MainActivity.RECORD_ACTION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        )
        hide()
    }
}

/// Some Android versions reject an assistant without a recognition service.
class TyLogRecognitionService : RecognitionService() {
    override fun onStartListening(intent: Intent?, callback: Callback?) {}
    override fun onCancel(callback: Callback?) {}
    override fun onStopListening(callback: Callback?) {}
}
