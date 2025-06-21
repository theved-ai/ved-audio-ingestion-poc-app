./AudioHelper com.google.Chrome --dry-mic | ffmpeg -f s16le -ar 48000 -ac 2 -i - -f wav - | ffplay - ==> only tab audio

./AudioHelper com.google.Chrome --dry-tab | ffmpeg -f f32le -ar 48000 -ac 1 -i - -f wav - | ffplay - ==> only mic audio


swift build -c release => build the swift project