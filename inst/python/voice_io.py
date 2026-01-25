"""
Voice I/O module for counselor package.

Provides speech-to-text (via Deepgram) and text-to-speech (via Cartesia)
functionality using Pipecat services.
"""

import io
import os
import wave
from typing import Optional

# Audio recording settings
SAMPLE_RATE = 16000
CHANNELS = 1
CHUNK_SIZE = 1024
RECORD_SECONDS_DEFAULT = 10


class VoiceIO:
    """Voice input/output handler using Deepgram STT and Cartesia TTS."""

    def __init__(
        self,
        deepgram_api_key: Optional[str] = None,
        cartesia_api_key: Optional[str] = None,
        voice_id: str = "a0e99841-438c-4a64-b679-ae501e7d6091",  # Cartesia default
    ):
        """
        Initialize voice I/O with API credentials.

        Args:
            deepgram_api_key: Deepgram API key (or uses DEEPGRAM_API_KEY env var)
            cartesia_api_key: Cartesia API key (or uses CARTESIA_API_KEY env var)
            voice_id: Cartesia voice ID for TTS
        """
        self.deepgram_key = deepgram_api_key or os.getenv("DEEPGRAM_API_KEY")
        self.cartesia_key = cartesia_api_key or os.getenv("CARTESIA_API_KEY")
        self.voice_id = voice_id

        if not self.deepgram_key:
            raise ValueError("DEEPGRAM_API_KEY not set")
        if not self.cartesia_key:
            raise ValueError("CARTESIA_API_KEY not set")

        # Lazy import pyaudio to avoid issues if not installed
        import pyaudio

        self.pyaudio = pyaudio.PyAudio()

        # Initialize Deepgram client
        from deepgram import DeepgramClient

        self.deepgram = DeepgramClient(self.deepgram_key)

        # Initialize Cartesia client
        from cartesia import Cartesia

        self.cartesia = Cartesia(api_key=self.cartesia_key)

    def __del__(self):
        """Clean up PyAudio resources."""
        if hasattr(self, "pyaudio"):
            self.pyaudio.terminate()

    def listen(self, timeout_secs: float = RECORD_SECONDS_DEFAULT) -> str:
        """
        Record audio from microphone and transcribe with Deepgram.

        Args:
            timeout_secs: Maximum recording duration in seconds.

        Returns:
            Transcribed text from the audio.
        """
        import pyaudio

        # Record audio
        stream = self.pyaudio.open(
            format=pyaudio.paInt16,
            channels=CHANNELS,
            rate=SAMPLE_RATE,
            input=True,
            frames_per_buffer=CHUNK_SIZE,
        )

        print(f"Listening... (up to {timeout_secs}s)")
        frames = []

        # Simple recording - in production, use VAD for smarter cutoff
        num_chunks = int(SAMPLE_RATE / CHUNK_SIZE * timeout_secs)
        for _ in range(num_chunks):
            try:
                data = stream.read(CHUNK_SIZE, exception_on_overflow=False)
                frames.append(data)
            except Exception as e:
                print(f"Recording error: {e}")
                break

        stream.stop_stream()
        stream.close()
        print("Processing speech...")

        # Convert to WAV format in memory
        audio_buffer = io.BytesIO()
        with wave.open(audio_buffer, "wb") as wf:
            wf.setnchannels(CHANNELS)
            wf.setsampwidth(self.pyaudio.get_sample_size(pyaudio.paInt16))
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(b"".join(frames))

        audio_buffer.seek(0)

        # Transcribe with Deepgram
        from deepgram import PrerecordedOptions

        payload = {"buffer": audio_buffer.read()}
        options = PrerecordedOptions(
            model="nova-2",
            smart_format=True,
            language="en",
        )

        response = self.deepgram.listen.rest.v("1").transcribe_file(payload, options)

        # Extract transcript
        transcript = ""
        if response.results and response.results.channels:
            channel = response.results.channels[0]
            if channel.alternatives:
                transcript = channel.alternatives[0].transcript

        return transcript.strip()

    def speak(self, text: str) -> None:
        """
        Synthesize text to speech with Cartesia and play through speakers.

        Args:
            text: The text to speak.
        """
        if not text:
            return

        import pyaudio

        print(f"Speaking: {text[:50]}...")

        # Generate audio with Cartesia (v2 API)
        # The bytes() method returns an iterator, so we collect all chunks
        audio_chunks = self.cartesia.tts.bytes(
            model_id="sonic-2",
            transcript=text,
            voice={"id": self.voice_id},
            output_format={
                "container": "raw",
                "encoding": "pcm_s16le",
                "sample_rate": 24000,
            },
            language="en",
        )

        # Collect all audio chunks
        audio_data = b"".join(audio_chunks)

        # Play audio
        stream = self.pyaudio.open(
            format=pyaudio.paInt16,
            channels=1,
            rate=24000,
            output=True,
        )

        stream.write(audio_data)
        stream.stop_stream()
        stream.close()


# Convenience functions for R interface


def create_voice_io(
    deepgram_key: Optional[str] = None,
    cartesia_key: Optional[str] = None,
    voice_id: str = "a0e99841-438c-4a64-b679-ae501e7d6091",
) -> VoiceIO:
    """Create a VoiceIO instance."""
    return VoiceIO(deepgram_key, cartesia_key, voice_id)


def listen_once(voice_io: VoiceIO, timeout_secs: float = 10.0) -> str:
    """Listen for speech and return transcript."""
    return voice_io.listen(timeout_secs)


def speak_text(voice_io: VoiceIO, text: str) -> None:
    """Speak the given text."""
    voice_io.speak(text)
