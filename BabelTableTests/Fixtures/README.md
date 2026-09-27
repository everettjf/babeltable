# Offline speech fixture

`english.wav` is synthetic speech generated locally with macOS's Samantha voice:

> Hello. Thank you for your help.

24 kHz mono PCM16 WAV, generated with `say -v Samantha -r 140 --file-format=WAVE --data-format=LEI16@24000`.
It contains no user recording or private conversation. Device integration tests feed it directly to the local speech pipeline; they never open the microphone or download models.
