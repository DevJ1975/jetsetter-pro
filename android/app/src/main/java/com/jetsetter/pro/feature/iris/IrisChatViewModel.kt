package com.jetsetter.pro.feature.iris

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.jetsetter.pro.core.data.remote.ClaudeMessage
import com.jetsetter.pro.core.data.repository.IrisRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ChatMessage(val text: String, val fromUser: Boolean)

@HiltViewModel
class IrisChatViewModel @Inject constructor(
    private val irisRepository: IrisRepository,
) : ViewModel() {

    private val _messages = MutableStateFlow(
        listOf(
            ChatMessage(
                "Hi, I'm IRIS — your travel concierge. Ask me about your flights, itinerary, packing, or expenses.",
                fromUser = false,
            ),
        ),
    )
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _isThinking = MutableStateFlow(false)
    val isThinking: StateFlow<Boolean> = _isThinking.asStateFlow()

    fun send(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || _isThinking.value) return

        val history = _messages.value + ChatMessage(trimmed, fromUser = true)
        _messages.value = history
        _isThinking.value = true

        viewModelScope.launch {
            val claudeHistory = history.map { ClaudeMessage(if (it.fromUser) "user" else "assistant", it.text) }
            val reply = irisRepository.ask(claudeHistory)
            _messages.value = _messages.value + ChatMessage(reply, fromUser = false)
            _isThinking.value = false
        }
    }
}
