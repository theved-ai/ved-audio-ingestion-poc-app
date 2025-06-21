console.log('>>> renderer.js injected');

const { ipcRenderer } = require('electron');
const { spawn }      = require('child_process');

/* ---------------- request helper path from main ---------------- */

ipcRenderer.invoke('get-helper-path').then(helperPath => {
  console.log('[renderer] helperPath =', helperPath);

  /* ---------- constants ---------- */
  const HELPER   = helperPath;            // ← use the value we just got
  const WS_URL   = 'ws://localhost:8000/v1/ingest/audio';
  const USER_ID  = '7dcb16b8-c05c-4ec4-9524-0003e11acd2a';
  const CHUNK_MS = 3000;

  /* ---------- state ---------- */
  let proc, ws, buffers = [], timerId = 0, idx = 0, rawDataId = null;

  /* ---------- UI ---------- */
  const btn = document.getElementById('recBtn');
  btn.addEventListener('click', () => (proc ? stop() : start()));

  /* ---------------- functions ---------------- */

  function start() {
    ws = new WebSocket(WS_URL);

    ws.onopen = () => ws.send(JSON.stringify({
      event_type: 'init',
      payload: { input_data_source: 'meet_transcript', user_id: USER_ID }
    }));

    ws.onmessage = evt => {
      const m = JSON.parse(evt.data);
      if (m.status === 'SUCCESS') {
        rawDataId = m.raw_data_id;
        kickOffCapture();
      }
    };
  }

  function kickOffCapture() {
    proc = spawn(HELPER, ['com.google.Chrome'], { stdio: ['ignore','pipe','pipe'] });

    proc.stdout.on('data', chunk => {
      buffers.push(Buffer.from(chunk));
    });
    proc.stderr.on('data', d => console.log('[helper]', d.toString()));

    timerId = setInterval(() => {
      if (!buffers.length || ws.readyState !== WebSocket.OPEN) return;
      const chunk = Buffer.concat(buffers);
      buffers.length = 0;               // reset array
      if (chunk.length === 0) return;
      const b64 = chunk.toString('base64');
      ws.send(JSON.stringify({
        event_type: 'audio_chunk',
        payload: {
          input_data_source : 'meet_transcript',
          user_id           : USER_ID,
          raw_data_id       : rawDataId,
          audio_format      : 'f32le',
          audio_chunk_index : idx++,
          audio_blob        : b64
        }
      }));
    }, CHUNK_MS);


    btn.textContent = 'Stop';
  }

  function stop() {
    clearInterval(timerId);
    proc?.kill();           proc = null;
    buffers.length = 0;     idx = 0;

    if (ws?.readyState === 1) {
      ws.send(JSON.stringify({
        event_type: 'close_connection',
        payload: {
          input_data_source: 'meet_transcript',
          user_id          : USER_ID,
          raw_data_id      : rawDataId
        }
      }));
      ws.close();
    }
    rawDataId = null;
    btn.textContent = 'Start Recording';
  }

}).catch(err => {
  console.error('Failed to obtain helperPath from main:', err);
});
