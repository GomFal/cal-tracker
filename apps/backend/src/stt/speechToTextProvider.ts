export type TranscriptionResult = {
  text: string;
  language?: string;
  durationSeconds?: number;
  provider: string;
  model: string;
};

export type SpeechToTextInput = {
  audio: Buffer;
  filename: string;
  mimeType: string;
  userId: string;
  traceId: string;
};

export interface SpeechToTextProvider {
  transcribe(input: SpeechToTextInput): Promise<TranscriptionResult>;
}

export class RemoteSpeechToTextProvider implements SpeechToTextProvider {
  constructor(
    private readonly apiKey: string,
    private readonly model: string,
    private readonly baseUrl: string
  ) {}

  async transcribe(input: SpeechToTextInput): Promise<TranscriptionResult> {
    const startedAt = Date.now();
    const form = new FormData();
    const arrayBuffer = input.audio.buffer.slice(
      input.audio.byteOffset,
      input.audio.byteOffset + input.audio.byteLength
    ) as ArrayBuffer;
    const blob = new Blob([arrayBuffer], { type: input.mimeType });
    form.append("file", blob, input.filename);
    form.append("model", this.model);
    form.append("response_format", "json");
    form.append("temperature", "0");

    const res = await fetch(`${this.baseUrl}/audio/transcriptions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: form,
    });

    if (!res.ok) {
      const err = await res.text();
      console.error("stt.provider.failed", {
        traceId: input.traceId,
        provider: "groq",
        model: this.model,
        status: res.status,
        durationMs: Date.now() - startedAt,
        response: err.slice(0, 500),
      });
      throw new Error(`STT failed: ${res.status} ${err}`);
    }

    const json = (await res.json()) as { text: string };
    console.info("stt.provider.completed", {
      traceId: input.traceId,
      provider: "groq",
      model: this.model,
      durationMs: Date.now() - startedAt,
      transcriptLength: json.text.length,
    });

    return {
      text: json.text,
      provider: "groq",
      model: this.model,
    };
  }
}
