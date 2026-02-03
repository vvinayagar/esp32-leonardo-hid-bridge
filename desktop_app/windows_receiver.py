import queue
import socket
import threading
import time
import tkinter as tk
from tkinter import ttk

from pynput.keyboard import Controller as KeyboardController
from pynput.keyboard import Key
from pynput.mouse import Button
from pynput.mouse import Controller as MouseController


KEY_MAP = {
    "ENTER": Key.enter,
    "TAB": Key.tab,
    "ESC": Key.esc,
    "BACKSPACE": Key.backspace,
    "UP": Key.up,
    "DOWN": Key.down,
    "LEFT": Key.left,
    "RIGHT": Key.right,
}

MOUSE_MAP = {
    "LEFT": Button.left,
    "RIGHT": Button.right,
    "MIDDLE": Button.middle,
}


class CommandRunner:
    def __init__(self, log_cb, status_cb):
        self.log = log_cb
        self.status = status_cb
        self.keyboard = KeyboardController()
        self.mouse = MouseController()
        self.armed = False

    def handle_line(self, line, token):
        if not line:
            return
        if not line.startswith("TOKEN="):
            self.log("IGNORED: missing token")
            return
        idx = line.find(";")
        if idx < 0:
            self.log("IGNORED: invalid token format")
            return
        line_token = line[6:idx]
        if line_token != token:
            self.log("AUTH FAIL")
            return
        command = line[idx + 1 :].strip()
        self.handle_command(command)

    def handle_command(self, command):
        if command == "ARM:ON":
            self.armed = True
            self.status(self.armed)
            self.log("ARMED")
            return
        if command == "ARM:OFF":
            self.armed = False
            self.status(self.armed)
            self.log("DISARMED")
            return

        if not self.armed:
            self.log("IGNORED (DISARMED): " + command)
            return

        if command.startswith("TYPE:"):
            text = command[5:]
            self.keyboard.type(text)
            self.log("TYPE: " + text)
            return

        if command.startswith("KEY:"):
            self._send_key(command[4:])
            return

        if command.startswith("HOTKEY:"):
            self._send_hotkey(command[7:])
            return

        if command.startswith("DELAY:"):
            self._delay(command[6:])
            return

        if command.startswith("MOUSE:"):
            self._handle_mouse(command[6:])
            return

        self.log("UNKNOWN CMD: " + command)

    def _send_key(self, name):
        key = KEY_MAP.get(name)
        if key is None:
            if len(name) == 1:
                self.keyboard.press(name.lower())
                self.keyboard.release(name.lower())
                self.log("KEY: " + name)
            else:
                self.log("UNKNOWN KEY: " + name)
            return
        self.keyboard.press(key)
        self.keyboard.release(key)
        self.log("KEY: " + name)

    def _send_hotkey(self, combo):
        parts = [part.strip().upper() for part in combo.split("+") if part.strip()]
        if not parts:
            self.log("HOTKEY missing final key")
            return
        mods = []
        final_key = None
        for token in parts:
            if token == "CTRL":
                mods.append(Key.ctrl)
            elif token == "ALT":
                mods.append(Key.alt)
            elif token == "SHIFT":
                mods.append(Key.shift)
            elif token == "WIN":
                mods.append(Key.cmd)
            else:
                final_key = token

        if not final_key:
            self.log("HOTKEY missing final key")
            return

        for mod in mods:
            self.keyboard.press(mod)

        key = KEY_MAP.get(final_key)
        if key is None:
            if len(final_key) == 1:
                self.keyboard.press(final_key.lower())
                self.keyboard.release(final_key.lower())
            else:
                self.log("UNKNOWN HOTKEY: " + final_key)
                for mod in mods:
                    self.keyboard.release(mod)
                return
        else:
            self.keyboard.press(key)
            self.keyboard.release(key)

        for mod in mods:
            self.keyboard.release(mod)
        self.log("HOTKEY: " + combo)

    def _delay(self, value):
        try:
            ms = int(value)
        except ValueError:
            self.log("DELAY invalid: " + value)
            return
        ms = max(0, min(5000, ms))
        self.log("DELAY: " + str(ms))
        time.sleep(ms / 1000.0)

    def _handle_mouse(self, payload):
        if ":" in payload:
            action, args = payload.split(":", 1)
        else:
            action, args = payload, ""
        action = action.strip().upper()
        args = args.strip()

        if action == "MOVE":
            self._mouse_move(args)
            return
        if action == "SCROLL":
            self._mouse_scroll(args)
            return
        if action in ("DOWN", "UP", "CLICK"):
            self._mouse_button(action, args)
            return
        self.log("UNKNOWN MOUSE CMD: " + payload)

    def _mouse_move(self, args):
        if "," not in args:
            self.log("MOUSE MOVE invalid args")
            return
        dx_str, dy_str = args.split(",", 1)
        try:
            dx = int(dx_str.strip())
            dy = int(dy_str.strip())
        except ValueError:
            self.log("MOUSE MOVE invalid args")
            return
        self.mouse.move(dx, dy)
        self.log("MOUSE MOVE: {},{}".format(dx, dy))

    def _mouse_scroll(self, args):
        if "," in args:
            args = args.split(",", 1)[1].strip()
        try:
            dy = int(args) if args else 0
        except ValueError:
            self.log("MOUSE SCROLL invalid args")
            return
        self.mouse.scroll(0, dy)
        self.log("MOUSE SCROLL: " + str(dy))

    def _mouse_button(self, action, button_name):
        button = MOUSE_MAP.get(button_name.upper())
        if button is None:
            self.log("UNKNOWN MOUSE BUTTON: " + button_name)
            return
        if action == "DOWN":
            self.mouse.press(button)
        elif action == "UP":
            self.mouse.release(button)
        elif action == "CLICK":
            self.mouse.click(button)
        self.log("MOUSE {}: {}".format(action, button_name))


class ReceiverApp:
    def __init__(self, root):
        self.root = root
        self.root.title("ESP HID Desktop Receiver")
        self.root.geometry("720x520")

        self.running = False
        self.sock = None
        self.recv_thread = None
        self.worker_thread = None

        self.command_queue = queue.Queue()
        self.log_queue = queue.Queue()

        self.token = "1234"
        self.port = 51515
        self.bind_addr = "0.0.0.0"
        self.token_lock = threading.Lock()

        self.runner = CommandRunner(self._log, self._update_armed)

        self._build_ui()
        self._poll_queues()

    def _build_ui(self):
        config_frame = ttk.LabelFrame(self.root, text="Configuration")
        config_frame.pack(fill="x", padx=10, pady=10)

        ttk.Label(config_frame, text="Token").grid(row=0, column=0, padx=6, pady=6)
        self.token_var = tk.StringVar(value=self.token)
        ttk.Entry(config_frame, textvariable=self.token_var, width=20).grid(
            row=0, column=1, padx=6, pady=6
        )

        ttk.Label(config_frame, text="UDP Port").grid(
            row=0, column=2, padx=6, pady=6
        )
        self.port_var = tk.StringVar(value=str(self.port))
        ttk.Entry(config_frame, textvariable=self.port_var, width=10).grid(
            row=0, column=3, padx=6, pady=6
        )

        self.start_button = ttk.Button(
            config_frame, text="Start", command=self.start
        )
        self.start_button.grid(row=0, column=4, padx=6, pady=6)

        self.stop_button = ttk.Button(config_frame, text="Stop", command=self.stop)
        self.stop_button.grid(row=0, column=5, padx=6, pady=6)

        status_frame = ttk.Frame(self.root)
        status_frame.pack(fill="x", padx=10)

        self.status_var = tk.StringVar(value="Stopped")
        ttk.Label(status_frame, textvariable=self.status_var).pack(
            side="left", padx=6
        )

        self.armed_var = tk.StringVar(value="Disarmed")
        ttk.Label(status_frame, textvariable=self.armed_var).pack(
            side="left", padx=12
        )

        clear_btn = ttk.Button(status_frame, text="Clear Log", command=self._clear_log)
        clear_btn.pack(side="right", padx=6)

        log_frame = ttk.LabelFrame(self.root, text="Log")
        log_frame.pack(fill="both", expand=True, padx=10, pady=10)
        self.log_text = tk.Text(log_frame, wrap="word", height=20)
        self.log_text.pack(fill="both", expand=True)

    def _clear_log(self):
        self.log_text.delete("1.0", tk.END)

    def _log(self, message):
        self.log_queue.put(("log", message))

    def _update_armed(self, armed):
        self.log_queue.put(("armed", armed))

    def _poll_queues(self):
        while True:
            try:
                item = self.log_queue.get_nowait()
            except queue.Empty:
                break
            kind, payload = item
            if kind == "log":
                self.log_text.insert(tk.END, payload + "\n")
                self.log_text.see(tk.END)
            elif kind == "armed":
                self.armed_var.set("Armed" if payload else "Disarmed")
        self.root.after(100, self._poll_queues)

    def _apply_config(self):
        token = self.token_var.get().strip()
        if not token:
            token = "1234"
        port_str = self.port_var.get().strip()
        try:
            port = int(port_str)
        except ValueError:
            port = 51515
        port = max(1, min(65535, port))
        with self.token_lock:
            self.token = token
            self.port = port

    def start(self):
        if self.running:
            return
        self._apply_config()
        self.running = True
        self.status_var.set("Running on UDP {}".format(self.port))

        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.bind((self.bind_addr, self.port))
            self.sock.settimeout(0.5)
        except OSError as exc:
            self.sock = None
            self.running = False
            self.status_var.set("Stopped")
            self._log("Failed to bind UDP: {}".format(exc))
            return

        self.recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
        self.recv_thread.start()

        self.worker_thread = threading.Thread(target=self._worker_loop, daemon=True)
        self.worker_thread.start()

        self._log("Receiver started")

    def stop(self):
        self.running = False
        self.status_var.set("Stopped")
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        self._log("Receiver stopped")

    def _recv_loop(self):
        while self.running and self.sock:
            try:
                data, _addr = self.sock.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                line = data.decode("utf-8", errors="ignore").strip()
            except UnicodeDecodeError:
                continue
            if line:
                self.command_queue.put(line)

    def _worker_loop(self):
        while self.running:
            try:
                line = self.command_queue.get(timeout=0.5)
            except queue.Empty:
                continue
            token = self._get_token()
            self.runner.handle_line(line, token)

    def _get_token(self):
        with self.token_lock:
            return self.token

    def shutdown(self):
        self.stop()
        self.root.destroy()


def main():
    root = tk.Tk()
    app = ReceiverApp(root)
    root.protocol("WM_DELETE_WINDOW", app.shutdown)
    root.mainloop()


if __name__ == "__main__":
    main()
