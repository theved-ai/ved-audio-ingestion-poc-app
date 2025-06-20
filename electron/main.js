// electron/main.js
// ────────────────────────────────────────────────────────────
const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');

function createWindow () {
  const win = new BrowserWindow({
    width: 400,
    height: 200,
    webPreferences: {
      nodeIntegration  : true,   // PoC convenience
      contextIsolation : false   // ↖ tighten for production
    }
  });

  // Load renderer.html that in turn loads renderer.js
  win.loadFile(path.join(__dirname, 'renderer.html'));
  win.webContents.openDevTools({ mode: 'detach' }); // remove later
}

/* ───────────────────────── app lifecycle ───────────────────────── */

app.whenReady().then(() => {
  // Helper binary that ScreenCaptureKit writes PCM to
  global.helperPath = path.join(__dirname, '..', 'mac-helper',
                                '.build', 'release', 'AudioHelper');

  // IPC: renderer asks for helperPath → we return it
  ipcMain.handle('get-helper-path', () => global.helperPath);

  createWindow();

  // macOS behaviour: reopen window on dock click
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

// quit on last-window-closed except on macOS
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
